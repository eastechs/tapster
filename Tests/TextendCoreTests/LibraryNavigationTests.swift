import XCTest

@testable import TextendCore

final class LibraryNavigationTests: XCTestCase {
  @MainActor private func fixture() throws -> (
    state: AppState, source: SnippetRecord, composition: SnippetRecord, collection: CollectionRecord
  ) {
    let store = try LibraryStore(inMemory: true)
    let collection = CollectionRecord(name: "Personal")
    try store.saveCollection(collection)
    let source = SnippetRecord(
      name: "Greeting", template: "Hello", collectionID: collection.id, isFavorite: true)
    let composition = SnippetRecord(
      name: "Combined Greeting", collectionID: collection.id, isFavorite: true,
      blocks: [.init(snippetID: source.id)])
    try store.save(source)
    try store.save(composition)
    let preferences = UserDefaults(suiteName: "TextendNavigationTests.\(UUID().uuidString)")!
    return (
      AppState(store: store, startEngine: false, preferences: preferences), source, composition,
      collection
    )
  }

  @MainActor func testPrimaryListsStaySeparateWhileFavoritesAndCollectionsIncludeBothTypes() throws
  {
    let f = try fixture()
    XCTAssertEqual(f.state.filteredSnippets.map(\.id), [f.source.id])
    f.state.selectScope(.compositions)
    XCTAssertEqual(f.state.filteredSnippets.map(\.id), [f.composition.id])
    f.state.search = "Greeting"
    XCTAssertEqual(f.state.filteredSnippets.map(\.id), [f.composition.id])
    f.state.selectScope(.all)
    XCTAssertEqual(f.state.filteredSnippets.map(\.id), [f.source.id])
    f.state.selectScope(.favorites)
    XCTAssertEqual(Set(f.state.filteredSnippets.map(\.id)), [f.source.id, f.composition.id])
    f.state.selectScope(.collection(f.collection.id))
    XCTAssertEqual(Set(f.state.filteredSnippets.map(\.id)), [f.source.id, f.composition.id])
  }

  @MainActor func testCreationRoutesToMatchingListAndPreservesCollectionAssignment() throws {
    let f = try fixture()
    f.state.selectScope(.collection(f.collection.id))
    f.state.search = "Nothing matches"
    f.state.newComposition()
    XCTAssertEqual(f.state.scope, .compositions)
    XCTAssertEqual(f.state.search, "")
    XCTAssertEqual(f.state.draft?.collectionID, f.collection.id)
    XCTAssertTrue(f.state.isNewDraft)
    XCTAssertEqual(f.state.unsavedSnippets.count, 1)
    XCTAssertTrue(f.state.unsavedSnippets.allSatisfy(\.isComposition))
    f.state.draft?.blocks = [.init(snippetID: f.source.id)]
    XCTAssertTrue(f.state.save())
    XCTAssertTrue(f.state.unsavedSnippets.isEmpty)
    XCTAssertTrue(f.state.filteredSnippets.contains { $0.id == f.state.selectedID })

    f.state.newSnippet()
    XCTAssertEqual(f.state.scope, .all)
    XCTAssertFalse(try XCTUnwrap(f.state.draft).isComposition)
    XCTAssertEqual(f.state.unsavedSnippets.count, 1)
    XCTAssertTrue(f.state.filteredSnippets.allSatisfy { !$0.isComposition })
  }

  @MainActor func testCancelledOrFailedDraftTransitionDoesNotSwitchSections() throws {
    let f = try fixture()
    f.state.draft?.template = "Unsaved edit"
    f.state.newComposition()
    XCTAssertTrue(f.state.showingUnsavedAlert)
    XCTAssertEqual(f.state.scope, .all)
    f.state.cancelTransition()
    XCTAssertEqual(f.state.selectedID, f.source.id)
    XCTAssertEqual(f.state.draft?.template, "Unsaved edit")

    f.state.newComposition()
    f.state.resolveUnsaved(save: false)
    XCTAssertEqual(f.state.scope, .compositions)
    let newID = f.state.selectedID
    f.state.newSnippet()
    f.state.resolveUnsaved(save: true)
    XCTAssertEqual(f.state.scope, .compositions)
    XCTAssertEqual(f.state.selectedID, newID)
    XCTAssertNotNil(f.state.errorMessage)

    f.state.draft?.blocks = [.init(snippetID: f.source.id)]
    f.state.newSnippet()
    f.state.resolveUnsaved(save: true)
    XCTAssertEqual(f.state.scope, .all)
    XCTAssertFalse(try XCTUnwrap(f.state.draft).isComposition)
  }

  @MainActor func testOpeningSourceRevealsItOutsideCompositionSearch() throws {
    let f = try fixture()
    f.state.select(f.composition.id)
    XCTAssertEqual(f.state.scope, .compositions)
    f.state.search = "Combined"
    f.state.select(f.source.id)
    XCTAssertEqual(f.state.scope, .all)
    XCTAssertEqual(f.state.search, "")
    XCTAssertEqual(f.state.selectedID, f.source.id)
    XCTAssertEqual(f.state.filteredSnippets.map(\.id), [f.source.id])
  }

  @MainActor func testDeletingCollectionKeepsSelectedCompositionVisible() throws {
    for remote in [false, true] {
      let f = try fixture()
      f.state.selectScope(.collection(f.collection.id))
      f.state.select(f.composition.id)
      f.state.search = f.collection.name
      if remote {
        try f.state.store.deleteCollection(f.collection.id)
      } else {
        f.state.deleteCollection(f.collection.id)
      }
      XCTAssertEqual(f.state.scope, .compositions)
      XCTAssertEqual(f.state.search, "")
      XCTAssertEqual(f.state.selectedID, f.composition.id)
      XCTAssertNil(f.state.draft?.collectionID)
      XCTAssertEqual(f.state.filteredSnippets.map(\.id), [f.composition.id])
    }
  }

  @MainActor func testCompositionOnlyLibraryStartsWithAnEmptySnippetList() throws {
    let store = try LibraryStore(inMemory: true)
    let composition = SnippetRecord(name: "Greeting", blocks: [.init(text: "Hello")])
    try store.save(composition)
    let state = AppState(store: store, startEngine: false)
    XCTAssertEqual(state.scope, .all)
    XCTAssertTrue(state.filteredSnippets.isEmpty)
    XCTAssertNil(state.draft)
    state.selectScope(.compositions)
    XCTAssertEqual(state.filteredSnippets.map(\.id), [composition.id])
    XCTAssertEqual(state.selectedID, composition.id)
  }

  func testSidebarSelectionStoragePreservesEverySectionAndLegacyValues() {
    let sections: [LibrarySelection] = [.all, .compositions, .favorites, .collection(UUID())]
    for section in sections {
      XCTAssertEqual(LibrarySelection(storedValue: section.storedValue), section)
    }
    XCTAssertEqual(LibrarySelection(storedValue: "unknown"), .all)
    XCTAssertEqual(LibrarySelection(storedValue: "all"), .all)
    XCTAssertEqual(LibrarySelection(storedValue: "favorites"), .favorites)
  }
}
