import Foundation
import Observation
import SwiftData

@MainActor @Observable final class LibraryStore {
  private(set) var snippets: [SnippetRecord] = []
  private(set) var collections: [CollectionRecord] = []
  private(set) var revision = 0
  private let container: ModelContainer
  private let context: ModelContext

  init(inMemory: Bool = false, url: URL? = nil) throws {
    let schema = Schema(versionedSchema: TapsterSchemaV1.self)
    let configuration: ModelConfiguration
    var legacyArchive: LibraryArchive?
    if let url {
      configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    } else if inMemory {
      configuration = ModelConfiguration(
        schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    } else {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )
      .appendingPathComponent("chat.eastechs.tapster", isDirectory: true)
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
      configuration = ModelConfiguration(
        schema: schema, url: support.appendingPathComponent("Library.store"),
        cloudKitDatabase: .none)
      // Preserve data created by the first development build, which used SwiftData's default URL.
      if UserDefaults.standard.bool(forKey: "hasCreatedLibrary")
        && !UserDefaults.standard.bool(forKey: "usesDedicatedLibrary")
      {
        let legacy = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if FileManager.default.fileExists(atPath: legacy.url.path) {
          let oldContainer = try ModelContainer(
            for: schema, migrationPlan: TapsterMigrationPlan.self, configurations: legacy)
          let oldContext = ModelContext(oldContainer)
          oldContext.autosaveEnabled = false
          legacyArchive = LibraryArchive(
            collections: try oldContext.fetch(FetchDescriptor<SavedCollection>()).map(\.record),
            snippets: try oldContext.fetch(FetchDescriptor<SavedSnippet>()).map { try $0.record() })
        }
      }
    }
    container = try ModelContainer(
      for: schema, migrationPlan: TapsterMigrationPlan.self, configurations: configuration)
    context = ModelContext(container)
    context.autosaveEnabled = false
    try reload()
    if let legacyArchive { try importArchive(JSONEncoder().encode(legacyArchive)) }
    if !inMemory && url == nil { UserDefaults.standard.set(true, forKey: "usesDedicatedLibrary") }
  }

  var archive: LibraryArchive { LibraryArchive(collections: collections, snippets: snippets) }

  func save(_ draft: SnippetRecord) throws {
    try LibraryValidation.validate(draft, among: snippets)
    guard draft.collectionID == nil || collections.contains(where: { $0.id == draft.collectionID })
    else {
      throw TemplateError.invalid("Choose an existing collection.")
    }
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
      } else {
        context.insert(SavedCollection(record))
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

  private func transaction(_ change: () throws -> Void) throws {
    do {
      try change()
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
    try reload()
  }

  private func reload() throws {
    let fetchedSnippets = try context.fetch(FetchDescriptor<SavedSnippet>()).map { try $0.record() }
    let fetchedCollections = try context.fetch(FetchDescriptor<SavedCollection>()).map(\.record)
    snippets = fetchedSnippets.sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    collections = fetchedCollections.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    revision += 1
  }
}
