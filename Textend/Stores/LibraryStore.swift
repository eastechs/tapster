import Foundation
import Observation
import SwiftData

@MainActor @Observable final class LibraryStore {
  private(set) var snippets: [SnippetRecord] = []
  private(set) var compositions: [CompositionRecord] = []
  var items: [SnippetRecord] {
    let snippetIDs = Set(snippets.map(\.id))
    return snippets + compositions.filter { !snippetIDs.contains($0.id) }.map(\.item)
  }
  var library: ExpansionLibrary {
    ExpansionLibrary(
      items: isSuspended ? [] : items, collections: collections, errors: recordErrors)
  }
  private var rawBlockData: [UUID: Data] = [:]
  private(set) var collections: [CollectionRecord] = []
  private(set) var revision = 0
  private var container: ModelContainer?
  private var context: ModelContext!
  private(set) var isSuspended = false
  private var rawPlaceholderData: [UUID: Data] = [:]
  var onChange: (() -> Void)?
  private(set) var recordErrors: [UUID: String] = [:]

  init(inMemory: Bool = false, url: URL? = nil, cloudContainer: String? = nil) throws {
    let schema = Schema(versionedSchema: TextendSchemaV3.self)
    let configuration: ModelConfiguration
    var legacyArchive: LibraryArchive?
    if let url {
      try StoreBackup.beforeMigration(at: url)
      configuration = ModelConfiguration(
        schema: schema, url: url, cloudKitDatabase: cloudContainer.map { .private($0) } ?? .none)
    } else if inMemory {
      configuration = ModelConfiguration(
        schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    } else {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )
      .appendingPathComponent(BuildIdentity.bundleID, isDirectory: true)
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
      try StoreBackup.beforeMigration(at: support.appendingPathComponent("Library.store"))
      configuration = ModelConfiguration(
        schema: schema, url: support.appendingPathComponent("Library.store"),
        cloudKitDatabase: .none)
      // Preserve data created by the first development build, which used SwiftData's default URL.
      if UserDefaults.standard.bool(forKey: "hasCreatedLibrary")
        && !UserDefaults.standard.bool(forKey: "usesDedicatedLibrary")
      {
        let legacy = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if FileManager.default.fileExists(atPath: legacy.url.path) {
          try StoreBackup.beforeMigration(at: legacy.url)
          let oldContainer = try ModelContainer(
            for: schema, migrationPlan: TextendMigrationPlan.self, configurations: legacy)
          let oldContext = ModelContext(oldContainer)
          oldContext.autosaveEnabled = false
          legacyArchive = LibraryArchive(
            collections: try oldContext.fetch(FetchDescriptor<SavedCollection>()).map(\.record),
            snippets: try oldContext.fetch(FetchDescriptor<SavedSnippet>()).map { try $0.record() })
        }
      }
    }
    let opened = try ModelContainer(
      for: schema, migrationPlan: TextendMigrationPlan.self, configurations: configuration)
    container = opened
    context = ModelContext(opened)
    context.autosaveEnabled = false
    try reload()
    if let legacyArchive { try importArchive(JSONEncoder().encode(legacyArchive)) }
    if !inMemory && url == nil { UserDefaults.standard.set(true, forKey: "usesDedicatedLibrary") }
  }

  var keywordConflicts: [String: [SnippetRecord]] {
    Dictionary(grouping: items.filter { !library.conflicts(for: $0).isEmpty }, by: \.keyword)
  }

  var expansionSnippets: [SnippetRecord] { library.automaticItems(in: nil) }

  func expansionIssue(for snippet: SnippetRecord) -> String? { library.issue(for: snippet) }

  var archive: LibraryArchive {
    LibraryArchive(collections: collections, snippets: snippets, compositions: compositions)
  }

  func libraryForDraft(_ draft: SnippetRecord) -> ExpansionLibrary {
    var value = library
    value.items = items.filter { $0.id != draft.id } + [draft]
    value.errors[draft.id] = nil
    return value
  }

  func validateSave(_ draft: SnippetRecord) throws {
    guard !(snippets.contains { $0.id == draft.id } && compositions.contains { $0.id == draft.id })
    else {
      throw TemplateError.invalid(
        "This identifier belongs to both a snippet and Composition. Resolve the identity conflict before saving."
      )
    }
    var proposed = library
    proposed.items = items.filter { $0.id != draft.id } + [draft]
    proposed.errors[draft.id] = nil  // A deliberate edit can repair unreadable stored content.
    try proposed.validateContent(draft)
    if let existing = items.first(where: { $0.id == draft.id }) {
      guard existing.isComposition == draft.isComposition else {
        throw TemplateError.invalid("This identifier already belongs to another item type.")
      }
    }
    let prior = items.first { $0.id == draft.id }
    if prior?.keyword != draft.keyword || prior?.collectionID != draft.collectionID
      || prior?.blocks != draft.blocks
    {
      try rejectNewConflicts(in: proposed)
    }
    guard
      draft.collectionID == nil || collections.contains(where: { $0.id == draft.collectionID })
        || prior?.collectionID == draft.collectionID
    else {
      throw TemplateError.invalid("Choose an existing collection.")
    }
  }

  private func rejectNewConflicts(in proposed: ExpansionLibrary) throws {
    for item in proposed.items {
      if proposed.conflicts(for: item).contains(where: {
        proposed.introducesConflict(item, with: $0, comparedTo: library)
      }) {
        try proposed.validateKeyword(item)
      }
    }
  }

  func save(_ draft: SnippetRecord) throws {
    try validateSave(draft)
    var record = draft
    record.updatedAt = Date()
    try transaction {
      if record.isComposition {
        if let saved = try context.fetch(FetchDescriptor<SavedComposition>()).first(where: {
          $0.id == record.id
        }) {
          try saved.apply(record)
        } else {
          context.insert(try SavedComposition(record))
        }
        return
      }
      let records = try context.fetch(FetchDescriptor<SavedSnippet>())
      if let saved = records.first(where: { $0.id == record.id }) {
        try saved.apply(record)
      } else {
        context.insert(try SavedSnippet(record))
      }
    }
  }

  func deleteSnippet(_ id: UUID) throws {
    try transaction {
      for item in try context.fetch(FetchDescriptor<SavedComposition>()) where item.id == id {
        context.delete(item)
      }
      for item in try context.fetch(FetchDescriptor<SavedSnippet>()) where item.id == id {
        context.delete(item)
      }
    }
  }

  func saveCollection(_ record: CollectionRecord) throws {
    try library.validateCollection(record)
    var proposed = library
    proposed.collections = collections.filter { $0.id != record.id } + [record]
    try rejectNewConflicts(in: proposed)
    try transaction {
      if let saved = try context.fetch(FetchDescriptor<SavedCollection>()).first(where: {
        $0.id == record.id
      }) {
        saved.name = record.name
        saved.sortOrder = record.sortOrder
        saved.appBundleIDs = record.appBundleIDs
        saved.updatedAt = Date()
      } else {
        let saved = SavedCollection(record)
        saved.updatedAt = Date()
        context.insert(saved)
      }
    }
  }

  func deleteCollection(_ id: UUID) throws {
    try transaction {
      for snippet in try context.fetch(FetchDescriptor<SavedSnippet>())
      where snippet.collectionID == id {
        snippet.collectionID = nil
        snippet.updatedAt = Date()
      }
      for item in try context.fetch(FetchDescriptor<SavedComposition>())
      where item.collectionID == id {
        item.collectionID = nil
        item.updatedAt = Date()
      }
      for collection in try context.fetch(FetchDescriptor<SavedCollection>())
      where collection.id == id { context.delete(collection) }
    }
  }

  func importArchive(_ data: Data) throws {
    let archive = try JSONDecoder().decode(LibraryArchive.self, from: data)
    try LibraryValidation.validateImport(archive, existing: self.archive)
    var proposed = library
    proposed.items += archive.snippets + archive.compositions.map(\.item)
    proposed.collections += archive.collections
    try rejectNewConflicts(in: proposed)
    try transaction {
      for collection in archive.collections { context.insert(SavedCollection(collection)) }
      for snippet in archive.snippets { context.insert(try SavedSnippet(snippet)) }
      for composition in archive.compositions {
        context.insert(try SavedComposition(composition.item))
      }
    }
  }

  func exportArchive() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(archive)
  }

  func seedExamples() throws {
    guard items.isEmpty && collections.isEmpty else { return }
    let development = CollectionRecord(name: "Development", sortOrder: 0)
    let personal = CollectionRecord(name: "Personal", sortOrder: 1)
    let samples = [
      SnippetRecord(
        name: "Git Commit", keyword: "gc", template: "git commit {commit_message}",
        collectionID: development.id,
        placeholders: [PlaceholderDefinition(name: "commit_message")]),
      SnippetRecord(
        name: "Git Checkout", keyword: "gco", template: "git checkout {branch}",
        collectionID: development.id,
        placeholders: [PlaceholderDefinition(name: "branch")]),
      SnippetRecord(
        name: "Email Signature", keyword: ";sig", template: "Best regards,\nDave",
        collectionID: personal.id, isFavorite: true),
      SnippetRecord(
        name: "Today's Date", keyword: ";date", template: "{today}", collectionID: personal.id,
        placeholders: [PlaceholderDefinition(name: "today", source: .dateTime)]),
    ]
    try transaction {
      context.insert(SavedCollection(development))
      context.insert(SavedCollection(personal))
      for sample in samples { context.insert(try SavedSnippet(sample)) }
    }
  }

  private struct Recovery: Codable {
    var archive: LibraryArchive
    var rawPlaceholders: [UUID: Data]
    var rawBlocks: [UUID: Data]? = nil
  }

  func recoveryData() throws -> Data {
    try JSONEncoder().encode(
      Recovery(archive: archive, rawPlaceholders: rawPlaceholderData, rawBlocks: rawBlockData))
  }

  func importRecovery(_ data: Data) throws {
    guard items.isEmpty && collections.isEmpty else {
      throw TemplateError.invalid("Recovery requires an empty local library.")
    }
    let recovery = try JSONDecoder().decode(Recovery.self, from: data)
    try transaction {
      for collection in recovery.archive.collections { context.insert(SavedCollection(collection)) }
      for composition in recovery.archive.compositions {
        let row = try SavedComposition(composition.item)
        if let data = recovery.rawBlocks?[composition.id] { row.blockData = data }
        context.insert(row)
      }
      for snippet in recovery.archive.snippets {
        let row = try SavedSnippet(snippet)
        if let data = recovery.rawPlaceholders[snippet.id] { row.placeholderData = data }
        context.insert(row)
      }
    }
  }

  func suspend() {
    isSuspended = true
    context = nil
    container = nil
    onChange?()
  }

  private func reconcileIdentities() throws {
    let snippetGroups = Dictionary(
      grouping: try context.fetch(FetchDescriptor<SavedSnippet>()), by: \.id)
    for group in snippetGroups.values where group.count > 1 {
      let sorted = group.sorted { ($0.updatedAt, $0.rowID) < ($1.updatedAt, $1.rowID) }
      guard let winner = sorted.last, let canonical = group.min(by: { $0.rowID < $1.rowID }) else {
        continue
      }
      if canonical !== winner {
        canonical.name = winner.name
        canonical.keyword = winner.keyword
        canonical.template = winner.template
        canonical.collectionID = winner.collectionID
        canonical.isFavorite = winner.isFavorite
        canonical.isEnabled = winner.isEnabled
        canonical.placeholderData = winner.placeholderData
        canonical.createdAt = winner.createdAt
        canonical.updatedAt = winner.updatedAt
      }
      for duplicate in group where duplicate !== canonical { context.delete(duplicate) }
    }
    let compositionGroups = Dictionary(
      grouping: try context.fetch(FetchDescriptor<SavedComposition>()), by: \.id)
    for group in compositionGroups.values where group.count > 1 {
      let sorted = group.sorted { ($0.updatedAt, $0.rowID) < ($1.updatedAt, $1.rowID) }
      guard let winner = sorted.last, let canonical = group.min(by: { $0.rowID < $1.rowID }) else {
        continue
      }
      if canonical !== winner {
        canonical.name = winner.name
        canonical.keyword = winner.keyword
        canonical.template = winner.template
        canonical.collectionID = winner.collectionID
        canonical.isFavorite = winner.isFavorite
        canonical.isEnabled = winner.isEnabled
        canonical.blockData = winner.blockData
        canonical.createdAt = winner.createdAt
        canonical.updatedAt = winner.updatedAt
      }
      for duplicate in group where duplicate !== canonical { context.delete(duplicate) }
    }
    let collectionGroups = Dictionary(
      grouping: try context.fetch(FetchDescriptor<SavedCollection>()), by: \.id)
    for group in collectionGroups.values where group.count > 1 {
      let sorted = group.sorted { ($0.updatedAt, $0.rowID) < ($1.updatedAt, $1.rowID) }
      guard let winner = sorted.last, let canonical = group.min(by: { $0.rowID < $1.rowID }) else {
        continue
      }
      canonical.name = winner.name
      canonical.sortOrder = winner.sortOrder
      canonical.appBundleIDs = winner.appBundleIDs
      canonical.updatedAt = winner.updatedAt
      for duplicate in group where duplicate !== canonical { context.delete(duplicate) }
    }
    if context.hasChanges { try context.save() }
  }

  private func transaction(_ change: () throws -> Void) throws {
    guard !isSuspended else {
      throw TemplateError.invalid(
        "Restart Textend after the iCloud account change. Your draft is still available.")
    }
    do {
      try change()
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
    try reload()
  }

  func reload() throws {
    guard let container, !isSuspended else {
      throw TemplateError.invalid("Restart Textend after the iCloud account change.")
    }
    context = ModelContext(container)
    context.autosaveEnabled = false
    try reconcileIdentities()
    var errors: [UUID: String] = [:]
    var raw: [UUID: Data] = [:]
    let fetchedSnippets = try context.fetch(FetchDescriptor<SavedSnippet>()).map { saved in
      raw[saved.id] = saved.placeholderData
      do { return try saved.record() } catch {
        errors[saved.id] =
          "Placeholder data couldn’t be read. Reassign the placeholder sources and save to repair this snippet."
        return SnippetRecord(
          id: saved.id, name: saved.name, keyword: saved.keyword,
          template: saved.template, collectionID: saved.collectionID, isFavorite: saved.isFavorite,
          isEnabled: saved.isEnabled, createdAt: saved.createdAt, updatedAt: saved.updatedAt)
      }
    }
    var rawBlocks: [UUID: Data] = [:]
    let fetchedCompositions = try context.fetch(FetchDescriptor<SavedComposition>()).map {
      saved -> CompositionRecord in
      rawBlocks[saved.id] = saved.blockData
      do { return CompositionRecord(try saved.record()) } catch {
        errors[saved.id] =
          "Composition blocks couldn’t be read. Rebuild the blocks and save to repair."
        return CompositionRecord(
          SnippetRecord(
            id: saved.id, name: saved.name, keyword: saved.keyword,
            collectionID: saved.collectionID, isFavorite: saved.isFavorite,
            isEnabled: saved.isEnabled,
            createdAt: saved.createdAt, updatedAt: saved.updatedAt, blocks: []))
      }
    }
    compositions = fetchedCompositions
    rawBlockData = rawBlocks
    let fetchedCollections = try context.fetch(FetchDescriptor<SavedCollection>()).map(\.record)
    snippets = fetchedSnippets.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    collections = fetchedCollections.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    let collisions = Set(fetchedSnippets.map(\.id)).intersection(fetchedCompositions.map(\.id))
    for id in collisions {
      errors[id] =
        "A snippet and Composition share this identifier. Export a recovery backup before repairing this library."
    }
    rawPlaceholderData = raw
    recordErrors = errors
    revision += 1
    onChange?()
  }
}
