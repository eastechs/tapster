import Foundation
import Observation
import SwiftData

@MainActor @Observable final class LibraryStore {
  private(set) var snippets: [SnippetRecord] = []
  private(set) var collections: [CollectionRecord] = []
  private(set) var revision = 0
  private var container: ModelContainer?
  private var context: ModelContext!
  private(set) var isSuspended = false
  private var rawPlaceholderData: [UUID: Data] = [:]
  var onChange: (() -> Void)?
  private(set) var recordErrors: [UUID: String] = [:]

  init(inMemory: Bool = false, url: URL? = nil, cloudContainer: String? = nil) throws {
    let schema = Schema(versionedSchema: TextendSchemaV2.self)
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
      .appendingPathComponent("chat.eastechs.tapster", isDirectory: true)
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
    Dictionary(grouping: snippets.filter { !$0.keyword.isEmpty }, by: \.keyword)
      .filter { $0.value.count > 1 }
  }

  var expansionSnippets: [SnippetRecord] {
    guard !isSuspended else { return [] }
    let conflicts = keywordConflicts
    return snippets.filter {
      $0.isEnabled && conflicts[$0.keyword] == nil && recordErrors[$0.id] == nil
        && (try? LibraryValidation.validate($0, among: [$0])) != nil
    }
  }

  func expansionIssue(for snippet: SnippetRecord) -> String? {
    if let error = recordErrors[snippet.id] { return error }
    if let conflicts = keywordConflicts[snippet.keyword] {
      return "Expansion paused: ‘\(snippet.keyword)’ is also used by "
        + conflicts.filter { $0.id != snippet.id }.map(\.name).joined(separator: ", ")
        + ". Rename or clear a keyword to resolve this conflict."
    }
    do {
      try LibraryValidation.validate(snippet, among: [snippet])
      return nil
    } catch { return error.localizedDescription }
  }

  var archive: LibraryArchive { LibraryArchive(collections: collections, snippets: snippets) }

  func validateSave(_ draft: SnippetRecord) throws {
    // Existing remote conflicts remain editable; only a newly introduced collision is rejected.
    let unchangedKeyword = snippets.contains { $0.id == draft.id && $0.keyword == draft.keyword }
    try LibraryValidation.validate(draft, among: unchangedKeyword ? [draft] : snippets)
    guard
      draft.collectionID == nil || collections.contains(where: { $0.id == draft.collectionID })
        || snippets.contains(where: { $0.id == draft.id && $0.collectionID == draft.collectionID })
    else {
      throw TemplateError.invalid("Choose an existing collection.")
    }
  }

  func save(_ draft: SnippetRecord) throws {
    try validateSave(draft)
    var record = draft
    record.updatedAt = Date()
    try transaction {
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
      for item in try context.fetch(FetchDescriptor<SavedSnippet>()) where item.id == id {
        context.delete(item)
      }
    }
  }

  func saveCollection(_ record: CollectionRecord) throws {
    guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TemplateError.invalid("Give this collection a name.")
    }
    try transaction {
      if let saved = try context.fetch(FetchDescriptor<SavedCollection>()).first(where: {
        $0.id == record.id
      }) {
        saved.name = record.name
        saved.sortOrder = record.sortOrder
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
      where snippet.collectionID == id { snippet.collectionID = nil }
      for collection in try context.fetch(FetchDescriptor<SavedCollection>())
      where collection.id == id { context.delete(collection) }
    }
  }

  func importArchive(_ data: Data) throws {
    let archive = try JSONDecoder().decode(LibraryArchive.self, from: data)
    try LibraryValidation.validateImport(archive, existing: self.archive)
    try transaction {
      for collection in archive.collections { context.insert(SavedCollection(collection)) }
      for snippet in archive.snippets { context.insert(try SavedSnippet(snippet)) }
    }
  }

  func exportArchive() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(archive)
  }

  func seedExamples() throws {
    guard snippets.isEmpty && collections.isEmpty else { return }
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
  }

  func recoveryData() throws -> Data {
    try JSONEncoder().encode(Recovery(archive: archive, rawPlaceholders: rawPlaceholderData))
  }

  func importRecovery(_ data: Data) throws {
    guard snippets.isEmpty && collections.isEmpty else {
      throw TemplateError.invalid("Recovery requires an empty local library.")
    }
    let recovery = try JSONDecoder().decode(Recovery.self, from: data)
    try transaction {
      for collection in recovery.archive.collections { context.insert(SavedCollection(collection)) }
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
    let collectionGroups = Dictionary(
      grouping: try context.fetch(FetchDescriptor<SavedCollection>()), by: \.id)
    for group in collectionGroups.values where group.count > 1 {
      let sorted = group.sorted { ($0.updatedAt, $0.rowID) < ($1.updatedAt, $1.rowID) }
      guard let winner = sorted.last, let canonical = group.min(by: { $0.rowID < $1.rowID }) else {
        continue
      }
      canonical.name = winner.name
      canonical.sortOrder = winner.sortOrder
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
    let fetchedCollections = try context.fetch(FetchDescriptor<SavedCollection>()).map(\.record)
    snippets = fetchedSnippets.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    collections = fetchedCollections.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    rawPlaceholderData = raw
    recordErrors = errors
    revision += 1
    onChange?()
  }
}
