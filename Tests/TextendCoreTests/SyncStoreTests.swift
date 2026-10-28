import SwiftData
import XCTest

@testable import TextendCore

final class SyncStoreTests: XCTestCase {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @MainActor func testV1MigrationPreservesLibraryAndRecoverableBackup() throws {
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Library.store")
    let collection = CollectionRecord(name: "Existing")
    let record = SnippetRecord(
      name: "Unicode", keyword: "hello", template: "Hello 🌎 {name}",
      collectionID: collection.id, isFavorite: true, placeholders: [.init(name: "name")])
    func writeLegacy() throws {
      let schema = Schema(versionedSchema: TextendSchemaV1.self)
      let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
      let context = ModelContext(container)
      context.insert(TextendSchemaV1.SavedCollection(collection))
      context.insert(try TextendSchemaV1.SavedSnippet(record))
      try context.save()
    }
    try writeLegacy()
    let store = try LibraryStore(url: url)
    XCTAssertEqual(store.snippets, [record])
    XCTAssertEqual(store.collections, [collection])
    let backup = url.appendingPathExtension("pre-v3.sqlite")
    XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    let schema = Schema(versionedSchema: TextendSchemaV1.self)
    let old = try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(schema: schema, url: backup, cloudKitDatabase: .none))
    XCTAssertEqual(
      try ModelContext(old).fetch(FetchDescriptor<TextendSchemaV1.SavedSnippet>()).first?.record(),
      record)
    XCTAssertEqual(try LibraryStore(url: url).archive, store.archive)
  }

  @MainActor func testRemoteChangesRefreshDraftAndSuppressDuplicateKeywords() throws {
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Library.store")
    let store = try LibraryStore(url: url)
    let first = SnippetRecord(name: "First", keyword: "gc", template: "Original")
    try store.save(first)
    let state = AppState(store: store, startEngine: false)
    let schema = Schema(versionedSchema: TextendSchemaV3.self)
    let remote = try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    let context = ModelContext(remote)
    let row = try XCTUnwrap(context.fetch(FetchDescriptor<SavedSnippet>()).first)
    row.template = "Remote"
    try context.save()
    try store.reload()
    XCTAssertEqual(state.draft?.template, "Remote")
    state.draft?.name = "Local name"
    row.template = "New remote template"
    try context.save()
    try store.reload()
    XCTAssertTrue(state.remoteDraftChanged)
    XCTAssertEqual(state.draft?.name, "Local name")
    XCTAssertTrue(state.save())
    XCTAssertEqual(store.snippets.first?.template, "New remote template")
    XCTAssertEqual(store.snippets.first?.name, "Local name")
    context.insert(try SavedSnippet(.init(name: "Conflict", keyword: "gc", template: "Other")))
    try context.save()
    try store.reload()
    XCTAssertEqual(store.keywordConflicts["gc"]?.count, 2)
    XCTAssertTrue(store.expansionSnippets.isEmpty)
    XCTAssertNil(state.copyError)
    XCTAssertNotNil(store.expansionIssue(for: first))
    state.draft?.isFavorite = true
    XCTAssertTrue(state.save(), "An existing remote conflict must remain editable")
    XCTAssertTrue(store.expansionSnippets.isEmpty)
    state.draft?.keyword = "gct"
    XCTAssertTrue(state.save())
    XCTAssertEqual(store.expansionSnippets.count, 2)
  }

  @MainActor func testRemoteDeleteKeepsDirtyDraftWithoutResurrection() throws {
    let store = try LibraryStore(inMemory: true)
    let snippet = SnippetRecord(name: "Test", keyword: "one", template: "Original")
    try store.save(snippet)
    let state = AppState(store: store, startEngine: false)
    state.draft?.template = "Unsaved"
    try store.deleteSnippet(snippet.id)
    XCTAssertTrue(state.remoteDraftDeleted)
    XCTAssertFalse(state.save())
    XCTAssertTrue(store.snippets.isEmpty)
    state.saveDeletedDraftAsNew()
    XCTAssertEqual(store.snippets.first?.template, "Unsaved")
    XCTAssertNotEqual(store.snippets.first?.id, snippet.id)
  }

  @MainActor func testIdentityReconciliationKeepsNewestValuesAndInvalidRowsVisible() throws {
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Library.store")
    let schema = Schema(versionedSchema: TextendSchemaV3.self)
    func writeDuplicates() throws {
      let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
      let context = ModelContext(container)
      let record = SnippetRecord(name: "Old", keyword: "x", template: "Old")
      let a = try SavedSnippet(record)
      a.rowID = "a"
      let b = try SavedSnippet(record)
      b.rowID = "b"
      b.updatedAt = a.updatedAt.addingTimeInterval(10)
      b.name = "Newest"
      b.placeholderData = Data([0xff])
      context.insert(a)
      context.insert(b)
      try context.save()
    }
    try writeDuplicates()
    let store = try LibraryStore(url: url)
    XCTAssertEqual(store.snippets.count, 1)
    XCTAssertEqual(store.snippets.first?.name, "Newest")
    XCTAssertEqual(store.recordErrors.count, 1)
    XCTAssertTrue(store.expansionSnippets.isEmpty)
    let container = try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    let rows = try ModelContext(container).fetch(FetchDescriptor<SavedSnippet>())
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.rowID, "a")
    XCTAssertEqual(rows.first?.placeholderData, Data([0xff]))
  }
  @MainActor func testPartialCollectionArrivalAndInvalidRecoveryRemainVisible() throws {
    let directory = try folder()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Library.store")
    let schema = Schema(versionedSchema: TextendSchemaV3.self)
    let remote = try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    let context = ModelContext(remote)
    let collection = CollectionRecord(name: "Arriving later")
    let snippet = SnippetRecord(
      name: "Partial", keyword: "part", template: "Text", collectionID: collection.id)
    let row = try SavedSnippet(snippet)
    row.placeholderData = Data([0xff])
    context.insert(row)
    try context.save()
    let store = try LibraryStore(url: url)
    XCTAssertEqual(store.snippets.first?.collectionID, collection.id)
    XCTAssertTrue(store.collections.isEmpty)
    XCTAssertTrue(store.expansionSnippets.isEmpty)
    let recovery = try LibraryStore(inMemory: true)
    try recovery.importRecovery(store.recoveryData())
    XCTAssertEqual(recovery.recordErrors.count, 1)
    XCTAssertTrue(recovery.expansionSnippets.isEmpty)
    var repaired = try XCTUnwrap(store.snippets.first)
    repaired.name = "Repaired"
    try store.save(repaired)
    // Missing collection fails closed until it arrives.
    XCTAssertTrue(store.expansionSnippets.isEmpty)
    context.insert(SavedCollection(collection))
    try context.save()
    try store.reload()
    XCTAssertEqual(store.collections, [collection])
    try store.deleteCollection(collection.id)
    XCTAssertEqual(store.snippets.count, 1)
    XCTAssertNil(store.snippets.first?.collectionID)
  }

}
