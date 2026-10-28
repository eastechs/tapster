import AppKit
import SwiftData
import XCTest

@testable import TextendCore

final class CompositionTests: XCTestCase {
  func testLiveReferencesSeparatorsAndLiteralBraces() throws {
    var a = SnippetRecord(
      name: "Greeting", template: "Hello {value}", placeholders: [.init(name: "value")])
    let b = SnippetRecord(
      name: "Date", template: "{value}",
      placeholders: [.init(name: "value", source: .dateTime, dateFormat: "yyyy")])
    let item = SnippetRecord(
      name: "Combined",
      blocks: [
        .init(snippetID: a.id, separator: .space), .init(text: "{literal}", separator: .paragraph),
        .init(snippetID: b.id, separator: .none), .init(snippetID: a.id),
      ])
    var library = ExpansionLibrary(items: [a, b, item])
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    XCTAssertEqual(
      try library.resolve(item, clipboard: "{clipboard}", date: date).text,
      "Hello {clipboard} {literal}\n\n2023Hello {clipboard}")
    a.template = "Updated"
    library.items[0] = a
    XCTAssertEqual(
      try library.resolve(item, clipboard: nil, date: date).text, "Updated {literal}\n\n2023Updated"
    )
  }

  func testCursorUsesCombinedUTF16OffsetAndRejectsRepeatedCursor() throws {
    let source = SnippetRecord(name: "Caret", template: "🌎{cursor}end")
    var item = SnippetRecord(
      name: "Combined", blocks: [.init(text: "é", separator: .line), .init(snippetID: source.id)])
    let library = ExpansionLibrary(items: [source, item])
    let result = try library.resolve(item, clipboard: nil)
    XCTAssertEqual(result.text, "é\n🌎end")
    XCTAssertEqual(result.cursorUTF16Offset, 4)
    item.blocks?.append(.init(snippetID: source.id))
    XCTAssertThrowsError(try library.resolve(item, clipboard: nil))
  }

  func testMissingNestedOrMalformedSourcesNeverProducePartialOutput() throws {
    let source = SnippetRecord(name: "Invalid", template: "{missing}")
    let nested = SnippetRecord(name: "Nested", blocks: [.init(text: "Hello")])
    var item = SnippetRecord(
      name: "Combined", blocks: [.init(text: "prefix"), .init(snippetID: source.id)])
    let library = ExpansionLibrary(items: [source, nested])
    XCTAssertThrowsError(try library.resolve(item, clipboard: nil))
    item.blocks?[1].snippetID = nested.id
    XCTAssertThrowsError(try library.resolve(item, clipboard: nil))
    item.blocks?[1].snippetID = UUID()
    XCTAssertThrowsError(try library.resolve(item, clipboard: nil))
  }

  func testScopeIntersectionAndDisabledSourceContent() throws {
    let first = CollectionRecord(name: "Writing", appBundleIDs: ["app.a", "app.b"])
    let second = CollectionRecord(name: "Code", appBundleIDs: ["app.b", "app.c"])
    let source = SnippetRecord(
      name: "Source", keyword: "same", template: "Hello", collectionID: first.id, isEnabled: false)
    let item = SnippetRecord(
      name: "Composition", keyword: "combo", collectionID: second.id,
      blocks: [.init(snippetID: source.id)])
    var library = ExpansionLibrary(items: [source, item], collections: [first, second])
    XCTAssertEqual(library.scope(of: item), ["app.b"])
    XCTAssertEqual(library.automaticItems(in: "app.b").map(\.id), [item.id])
    XCTAssertTrue(library.automaticItems(in: "app.a").isEmpty)
    XCTAssertEqual(try library.resolve(item, clipboard: nil).text, "Hello")
    library.collections[1].appBundleIDs = ["app.c"]
    XCTAssertEqual(library.scope(of: item), [])
    XCTAssertTrue(library.automaticItems(in: "app.b").isEmpty)
    XCTAssertEqual(try library.resolve(item, clipboard: nil).text, "Hello")
  }

  func testPrecedenceConflictsDisjointScopesAndDisabledOverrides() throws {
    let a = CollectionRecord(name: "A", appBundleIDs: ["app.a"])
    let b = CollectionRecord(name: "B", appBundleIDs: ["app.b"])
    let global = SnippetRecord(name: "Global", keyword: "key", template: "global")
    var specific = SnippetRecord(
      name: "Scoped", keyword: "key", template: "scoped", collectionID: a.id)
    let other = SnippetRecord(name: "Other", keyword: "key", template: "other", collectionID: b.id)
    var library = ExpansionLibrary(items: [global, specific, other], collections: [a, b])
    XCTAssertEqual(library.automaticItems(in: "app.a").map(\.id), [specific.id])
    XCTAssertEqual(library.automaticItems(in: "app.b").map(\.id), [other.id])
    XCTAssertEqual(library.automaticItems(in: "app.c").map(\.id), [global.id])
    try library.validateKeyword(specific)
    let duplicate = SnippetRecord(
      name: "Duplicate", keyword: "key", template: "duplicate", collectionID: a.id)
    library.items.append(duplicate)
    XCTAssertTrue(library.automaticItems(in: "app.a").isEmpty)
    XCTAssertThrowsError(try library.validateKeyword(duplicate))
    library.items.removeLast()
    specific.isEnabled = false
    library.items[1] = specific
    XCTAssertEqual(library.automaticItems(in: "app.a").map(\.id), [global.id])
    library.collections = []
    XCTAssertFalse(library.allows(specific, in: "app.a"))
  }

  @MainActor func testCompositionPersistenceDraftMergeDeletionAndBackup() throws {
    let store = try LibraryStore(inMemory: true)
    let source = SnippetRecord(name: "Source", template: "Hello")
    try store.save(source)
    let item = SnippetRecord(
      name: "Composition", keyword: "combo", blocks: [.init(snippetID: source.id)])
    try store.save(item)
    XCTAssertEqual(store.compositions.first?.item, store.items.first { $0.id == item.id })
    let state = AppState(store: store, startEngine: false)
    state.select(item.id)
    state.draft?.name = "Local name"
    var remote = item
    remote.blocks?.append(.init(text: "remote"))
    try store.save(remote)
    XCTAssertTrue(state.remoteDraftChanged)
    XCTAssertTrue(state.save())
    XCTAssertEqual(store.compositions.first?.metadata.name, "Local name")
    XCTAssertEqual(store.compositions.first?.blocks.count, 2)
    let destination = try LibraryStore(inMemory: true)
    try destination.importArchive(store.exportArchive())
    XCTAssertEqual(destination.archive, store.archive)
    try store.deleteSnippet(source.id)
    XCTAssertFalse(store.expansionSnippets.contains { $0.id == item.id })
    XCTAssertEqual(store.compositions.count, 1)
    try store.save(source)
    XCTAssertTrue(store.expansionSnippets.contains { $0.id == item.id })
    state.draft?.name = "Retained draft"
    try store.deleteSnippet(item.id)
    XCTAssertTrue(state.remoteDraftDeleted)
    XCTAssertFalse(state.save())
    state.saveDeletedDraftAsNew()
    XCTAssertEqual(store.compositions.count, 1)
    XCTAssertNotEqual(store.compositions.first?.id, item.id)
  }

  @MainActor func testCollectionScopeChangesRejectNewConflictsIncludingDependents() throws {
    let store = try LibraryStore(inMemory: true)
    let a = CollectionRecord(name: "A", appBundleIDs: ["app.a"])
    var b = CollectionRecord(name: "B", appBundleIDs: ["app.b"])
    try store.saveCollection(a)
    try store.saveCollection(b)
    let source = SnippetRecord(name: "Source", template: "Hello", collectionID: a.id)
    try store.save(source)
    try store.save(
      .init(name: "Composition", keyword: "key", blocks: [.init(snippetID: source.id)]))
    try store.save(.init(name: "Other", keyword: "key", template: "other", collectionID: b.id))
    b.appBundleIDs = ["app.a"]
    XCTAssertThrowsError(try store.saveCollection(b))
    XCTAssertEqual(store.collections.first { $0.id == b.id }?.appBundleIDs, ["app.b"])
  }

  @MainActor func testV2MigrationAndBackupRecoveryPreserveReleasedData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Library.store")
    let source = SnippetRecord(name: "Released", keyword: "key", template: "Hello")
    func seed() throws {
      let schema = Schema(versionedSchema: TextendSchemaV2.self)
      let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
      let context = ModelContext(container)
      context.insert(try TextendSchemaV2.SavedSnippet(source))
      try context.save()
    }
    try seed()
    let store = try LibraryStore(url: url)
    XCTAssertEqual(store.snippets, [source])
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: url.appendingPathExtension("pre-v3.sqlite").path))
    try store.save(.init(name: "Composition", blocks: [.init(snippetID: source.id)]))
    XCTAssertEqual(try LibraryStore(url: url).compositions, store.compositions)
  }

  @MainActor func testLegacyJSONImportAndAtomicBrokenCompositionImport() throws {
    let store = try LibraryStore(inMemory: true)
    let snippet = SnippetRecord(name: "Legacy", template: "Hi")
    let archive = LibraryArchive(version: 1, collections: [], snippets: [snippet])
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
    json.removeValue(forKey: "compositions")
    try store.importArchive(JSONSerialization.data(withJSONObject: json))
    XCTAssertEqual(store.snippets, [snippet])
    let bad = LibraryArchive(
      collections: [.init(name: "Should not save")], snippets: [],
      compositions: [CompositionRecord(.init(name: "Broken", blocks: [.init(snippetID: UUID())]))])
    XCTAssertThrowsError(try store.importArchive(JSONEncoder().encode(bad)))
    XCTAssertTrue(store.collections.isEmpty)
    XCTAssertTrue(store.compositions.isEmpty)
  }

  func testPaletteSearchIncludesManualItemsAndFiltersOtherApps() {
    let collection = CollectionRecord(name: "Mail", appBundleIDs: ["mail"])
    let source = SnippetRecord(
      name: "Signature", template: "Thank you", collectionID: collection.id)
    let item = SnippetRecord(
      name: "Message", isFavorite: true, isEnabled: false, blocks: [.init(snippetID: source.id)])
    let global = SnippetRecord(name: "Global", template: "Hi")
    let library = ExpansionLibrary(items: [source, item, global], collections: [collection])
    XCTAssertEqual(
      library.search("Thank", bundleID: "mail", allApps: false).map(\.id), [item.id, source.id])
    XCTAssertEqual(library.search("", bundleID: "other", allApps: false).map(\.id), [global.id])
    XCTAssertEqual(library.search("", bundleID: "other", allApps: true).count, 3)
  }

  @MainActor func testManualInsertionDoesNotDeleteKeywordAndRejectsChangedSelection() throws {
    let focus = InsertionTests.Focus()
    focus.range = CFRange(location: 4, length: 5)
    var events: [Int64] = []
    let service = TextInsertionService(
      focus: focus, secureInput: { false },
      postEvent: { events.append($0.getIntegerValueField(.keyboardEventKeycode)) })
    defer { service.finish() }
    try service.insert(
      .init(text: "Hello", cursorUTF16Offset: nil), target: XCTUnwrap(focus.value),
      selection: XCTUnwrap(focus.range), validate: { true })
    XCTAssertFalse(events.contains(51))
    service.finish()
    events = []
    XCTAssertThrowsError(
      try service.insert(
        .init(text: "Hello", cursorUTF16Offset: nil), target: XCTUnwrap(focus.value),
        selection: CFRange(location: 3, length: 5), validate: { true }))
    XCTAssertTrue(events.isEmpty)
    XCTAssertThrowsError(
      try service.insert(
        .init(text: "Hello", cursorUTF16Offset: nil), target: XCTUnwrap(focus.value),
        selection: XCTUnwrap(focus.range), validate: { false }))
    XCTAssertTrue(events.isEmpty)
  }
  func testInvalidScopesFailClosedAndConflictExpansionIsDetected() throws {
    var a = CollectionRecord(name: "A", appBundleIDs: ["app.a"])
    let b = CollectionRecord(name: "B", appBundleIDs: ["app.a", "app.b"])
    let first = SnippetRecord(name: "First", keyword: "key", template: "one", collectionID: a.id)
    let second = SnippetRecord(name: "Second", keyword: "key", template: "two", collectionID: b.id)
    let old = ExpansionLibrary(items: [first, second], collections: [a, b])
    XCTAssertFalse(old.introducesConflict(first, with: second, comparedTo: old))
    a.appBundleIDs = ["app.a", "app.b"]
    var proposed = ExpansionLibrary(items: old.items, collections: [a, b])
    XCTAssertTrue(proposed.introducesConflict(first, with: second, comparedTo: old))
    proposed.collections[0].appBundleIDs = [" "]
    XCTAssertFalse(proposed.allows(first, in: " "))
    XCTAssertThrowsError(try proposed.validateCollection(proposed.collections[0]))
    proposed.collections[0].appBundleIDs = []
    XCTAssertFalse(proposed.allows(first, in: "app.a"))
  }

  @MainActor func testImportCannotRestoreMissingCollectionIntoKeywordConflict() throws {
    try withRemoteStore { store, remote in
      let missing = CollectionRecord(name: "Arriving collection")
      remote.insert(try SavedSnippet(.init(name: "Global", keyword: "same", template: "one")))
      remote.insert(
        try SavedSnippet(
          .init(
            name: "Pending", keyword: "same", template: "two", collectionID: missing.id)))
      try remote.save()
      try store.reload()
      XCTAssertEqual(store.expansionSnippets.count, 1)
      let archive = LibraryArchive(collections: [missing], snippets: [])
      XCTAssertThrowsError(try store.importArchive(JSONEncoder().encode(archive)))
      XCTAssertTrue(store.collections.isEmpty)
      XCTAssertEqual(store.expansionSnippets.count, 1)
    }
  }

  @MainActor func testPartialRemoteSourcesAndCollectionsThenCompositionDraftMerge() throws {
    try withRemoteStore { store, remote in
      let collection = CollectionRecord(name: "Mail", appBundleIDs: ["mail"])
      let source = SnippetRecord(name: "Source", template: "Hello", collectionID: collection.id)
      let composition = SnippetRecord(
        name: "Pending", keyword: "combo", blocks: [.init(snippetID: source.id)])
      let savedComposition = try SavedComposition(composition)
      remote.insert(savedComposition)
      try remote.save()
      try store.reload()
      XCTAssertEqual(store.compositions.count, 1)
      XCTAssertTrue(store.library.automaticItems(in: "mail").isEmpty)
      remote.insert(try SavedSnippet(source))
      try remote.save()
      try store.reload()
      XCTAssertTrue(store.library.automaticItems(in: "mail").isEmpty)
      remote.insert(SavedCollection(collection))
      try remote.save()
      try store.reload()
      XCTAssertEqual(store.library.automaticItems(in: "mail").map(\.id), [composition.id])
      let state = AppState(store: store, startEngine: false)
      state.select(composition.id)
      state.draft?.name = "Local draft"
      var changed = composition
      changed.blocks?.append(.init(text: "Remote block"))
      try savedComposition.apply(changed)
      try remote.save()
      try store.reload()
      XCTAssertTrue(state.remoteDraftChanged)
      XCTAssertEqual(state.draft?.blocks?.count, 1)
      XCTAssertTrue(state.save())
      XCTAssertEqual(store.compositions.first?.metadata.name, "Local draft")
      XCTAssertEqual(store.compositions.first?.blocks.count, 2)
    }
  }

  @MainActor func testCompositionIdentityReconciliationPreservesMalformedRecovery() throws {
    try withRemoteStore { store, remote in
      let item = SnippetRecord(name: "Old", blocks: [.init(text: "Old text")])
      let first = try SavedComposition(item)
      first.rowID = "a"
      first.updatedAt = Date(timeIntervalSince1970: 1)
      let newer = try SavedComposition(item)
      newer.name = "Newer invalid data"
      newer.rowID = "b"
      newer.updatedAt = Date(timeIntervalSince1970: 2)
      newer.blockData = Data([0xFF])
      remote.insert(first)
      remote.insert(newer)
      try remote.save()
      try store.reload()
      XCTAssertEqual(store.compositions.count, 1)
      XCTAssertEqual(store.compositions.first?.metadata.name, "Newer invalid data")
      XCTAssertNotNil(store.recordErrors[item.id])
      let recovery = try store.recoveryData()
      let recovered = try LibraryStore(inMemory: true)
      try recovered.importRecovery(recovery)
      XCTAssertEqual(recovered.archive, store.archive)
      XCTAssertEqual(recovered.recordErrors, store.recordErrors)
      let decoded = try XCTUnwrap(
        JSONSerialization.jsonObject(with: recovered.recoveryData()) as? [String: Any])
      let original = try XCTUnwrap(
        JSONSerialization.jsonObject(with: recovery) as? [String: Any])
      XCTAssertEqual(decoded["rawBlocks"] as? NSObject, original["rawBlocks"] as? NSObject)
    }
  }

  @MainActor private func withRemoteStore(
    _ action: (LibraryStore, ModelContext) throws -> Void
  ) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Library.store")
    let store = try LibraryStore(url: url)
    let schema = Schema(versionedSchema: TextendSchemaV3.self)
    let container = try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    let context = ModelContext(container)
    context.autosaveEnabled = false
    try action(store, context)
  }
}
