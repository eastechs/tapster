import XCTest

@testable import TapsterCore

final class DraftTests: XCTestCase {
  @MainActor func testSortingPersistsWithoutChangingDraftOrFilteredMembership() throws {
    let suite = "TextendSortTests.\(UUID().uuidString)"
    let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let store = try LibraryStore(inMemory: true)
    let older = SnippetRecord(
      name: "Alpha", template: "Find me", isFavorite: true,
      createdAt: Date(timeIntervalSince1970: 1))
    let newer = SnippetRecord(
      name: "Zulu", template: "Find me", createdAt: Date(timeIntervalSince1970: 2))
    try store.save(newer)
    try store.save(older)
    let state = AppState(store: store, startEngine: false, preferences: preferences)
    XCTAssertEqual(state.filteredSnippets.map(\.id), [older.id, newer.id])
    XCTAssertEqual(state.sampleClipboard, "")
    state.draft?.template = "Unsaved edit"
    let selected = state.selectedID
    state.sortOrder = .createdAt
    XCTAssertEqual(state.filteredSnippets.map(\.id), [newer.id, older.id])
    XCTAssertEqual(state.selectedID, selected)
    XCTAssertEqual(state.draft?.template, "Unsaved edit")
    XCTAssertTrue(state.isDirty)
    XCTAssertFalse(state.showingUnsavedAlert)
    state.search = "find"
    state.scope = .favorites
    XCTAssertEqual(state.filteredSnippets.map(\.id), [older.id])
    state.scope = .all
    state.search = "Zulu"
    XCTAssertEqual(state.filteredSnippets.map(\.id), [newer.id])
    let restored = AppState(store: store, startEngine: false, preferences: preferences)
    XCTAssertEqual(restored.sortOrder, .createdAt)
    XCTAssertEqual(restored.filteredSnippets.map(\.id), [newer.id, older.id])
    preferences.set("unknown", forKey: "snippetSortOrder")
    XCTAssertEqual(
      AppState(store: store, startEngine: false, preferences: preferences).sortOrder, .name)
  }

  @MainActor private func state() throws -> AppState {
    let store = try LibraryStore(inMemory: true)
    try store.save(SnippetRecord(name: "First", keyword: "one", template: "Original"))
    try store.save(SnippetRecord(name: "Second", keyword: "two", template: "Other"))
    return AppState(store: store, seedExamples: false, startEngine: false)
  }

  @MainActor func testDraftChangesDoNotAffectStoreAndCancelKeepsDraft() throws {
    let state = try state()
    state.draft?.template = "Unsaved"
    XCTAssertEqual(state.store.snippets.first?.template, "Original")
    state.select(state.store.snippets.last?.id)
    XCTAssertTrue(state.showingUnsavedAlert)
    state.cancelTransition()
    XCTAssertEqual(state.draft?.template, "Unsaved")
    XCTAssertTrue(state.isDirty)
  }

  @MainActor func testDiscardThenSwitchAndSaveThenSwitch() throws {
    let state = try state()
    let firstID = try XCTUnwrap(state.selectedID)
    let secondID = try XCTUnwrap(state.store.snippets.last?.id)
    state.draft?.template = "Discard me"
    state.select(secondID)
    state.resolveUnsaved(save: false)
    XCTAssertEqual(state.selectedID, secondID)
    XCTAssertFalse(state.isDirty)
    XCTAssertEqual(state.store.snippets.first?.template, "Original")
    state.draft?.template = "Saved change"
    state.select(firstID)
    state.resolveUnsaved(save: true)
    XCTAssertEqual(state.selectedID, firstID)
    XCTAssertEqual(state.store.snippets.last?.template, "Saved change")
  }

  @MainActor func testFailedSaveDoesNotRunPendingAction() throws {
    let state = try state()
    let selected = state.selectedID
    state.draft?.name = ""
    state.select(state.store.snippets.last?.id)
    state.resolveUnsaved(save: true)
    XCTAssertEqual(state.selectedID, selected)
    XCTAssertNotNil(state.errorMessage)
    XCTAssertTrue(state.isDirty)
  }

  @MainActor func testDepartingEditorSurvivesClearedAndDeletedDrafts() throws {
    for delete in [false, true] {
      let state = try state()
      let original = try XCTUnwrap(state.draft)
      let binding = state.editorBinding(for: original)
      if delete {
        state.delete(original)
      } else {
        state.select(nil)
      }
      XCTAssertNil(state.draft)
      XCTAssertEqual(binding.wrappedValue, original)
      binding.wrappedValue.template = "Late callback"
      XCTAssertNil(state.draft)
      XCTAssertNil(state.selectedID)
      XCTAssertFalse(state.isDirty)
    }
  }

  @MainActor func testDepartingEditorCannotOverwriteAnotherSelection() throws {
    let state = try state()
    let original = try XCTUnwrap(state.draft)
    let binding = state.editorBinding(for: original)
    let next = try XCTUnwrap(state.store.snippets.last)
    state.select(next.id)
    XCTAssertEqual(binding.wrappedValue, original)
    binding.wrappedValue.template = "Late callback"
    XCTAssertEqual(state.draft, next)
    XCTAssertFalse(state.isDirty)
  }

  @MainActor func testEditorBindingTracksEditsAndSurvivesEmptyCollection() throws {
    let state = try state()
    let original = try XCTUnwrap(state.draft)
    let binding = state.editorBinding(for: original)
    binding.wrappedValue.template = "Changed through editor"
    XCTAssertEqual(state.draft?.template, "Changed through editor")
    XCTAssertTrue(state.isDirty)
    state.draft?.name = "Changed through state"
    XCTAssertEqual(binding.wrappedValue.name, "Changed through state")
    state.selectScope(.favorites)
    XCTAssertTrue(state.showingUnsavedAlert)
    state.resolveUnsaved(save: false)
    XCTAssertNil(state.draft)
    XCTAssertEqual(binding.wrappedValue.id, original.id)
    binding.wrappedValue.template = "Late callback"
    XCTAssertNil(state.draft)
    XCTAssertFalse(state.isDirty)
  }
}
