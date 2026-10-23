import XCTest

@testable import TapsterCore

final class StoreTests: XCTestCase {
  @MainActor func testSaveRelaunchAndCollectionDeletion() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("test.store")
    let store = try LibraryStore(url: url)
    let collection = CollectionRecord(name: "Work")
    try store.saveCollection(collection)
    let snippet = SnippetRecord(
      name: "Test", keyword: "test", template: "Hello", collectionID: collection.id)
    try store.save(snippet)
    let reopened = try LibraryStore(url: url)
    XCTAssertEqual(reopened.snippets.first?.template, "Hello")
    try reopened.deleteCollection(collection.id)
    XCTAssertEqual(reopened.snippets.count, 1)
    XCTAssertNil(reopened.snippets.first?.collectionID)
  }

  @MainActor func testInvalidSaveAndConflictingImportLeaveStoreUntouched() throws {
    let store = try LibraryStore(inMemory: true)
    let snippet = SnippetRecord(name: "Existing", keyword: "gc", template: "hello")
    try store.save(snippet)
    var invalid = snippet
    invalid.name = ""
    XCTAssertThrowsError(try store.save(invalid))
    XCTAssertEqual(store.snippets.first?.name, "Existing")
    let archive = LibraryArchive(
      collections: [.init(name: "Should not appear")],
      snippets: [SnippetRecord(name: "Conflict", keyword: "gc", template: "new")])
    XCTAssertThrowsError(try store.importArchive(JSONEncoder().encode(archive)))
    XCTAssertTrue(store.collections.isEmpty)
    XCTAssertEqual(store.snippets.count, 1)
  }

  @MainActor func testBackupRoundTripAndDuplicateIDRejected() throws {
    let source = try LibraryStore(inMemory: true)
    try source.seedExamples()
    let destination = try LibraryStore(inMemory: true)
    let data = try source.exportArchive()
    try destination.importArchive(data)
    XCTAssertEqual(source.archive, destination.archive)
    XCTAssertThrowsError(try destination.importArchive(data))
    XCTAssertEqual(destination.snippets.count, source.snippets.count)
  }
}
