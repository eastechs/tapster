import XCTest

@testable import TapsterCore

final class TransactionTests: XCTestCase {
  @MainActor final class Harness: ExpansionClipboard, ExpansionFocus, ExpansionInsertion {
    var target: ExpansionTarget? = ExpansionTarget(processID: 1, focusID: "field")
    var clipboard: String? = "Hello {literal}"
    var inserted: String?
    var cursorOffset: Int?
    var changesFocusOnRead = false
    func readText() -> String? {
      if changesFocusOnRead { target = nil }
      return clipboard
    }
    func currentTarget() -> ExpansionTarget? { target }
    func replace(
      keyword: String, with text: String, target: ExpansionTarget, cursorUTF16Offset: Int?
    ) throws {
      inserted = text
      cursorOffset = cursorUTF16Offset
    }
  }

  @MainActor func testResolveBeforeInsertionAndCancelOnFocusChange() throws {
    let harness = Harness()
    let target = try XCTUnwrap(harness.target)
    let snippet = SnippetRecord(
      name: "Test", keyword: "gc", template: "{message}", placeholders: [.init(name: "message")])
    try ExpansionTransaction.perform(
      snippet, target: target, clipboard: harness, focus: harness, insertion: harness)
    XCTAssertEqual(harness.inserted, "Hello {literal}")
    harness.inserted = nil
    harness.changesFocusOnRead = true
    XCTAssertThrowsError(
      try ExpansionTransaction.perform(
        snippet, target: target, clipboard: harness, focus: harness, insertion: harness))
    XCTAssertNil(harness.inserted)
  }

  @MainActor func testEmptyClipboardDoesNotRemoveKeyword() throws {
    let harness = Harness()
    harness.clipboard = nil
    let snippet = SnippetRecord(
      name: "Test", keyword: "gc", template: "{message}", placeholders: [.init(name: "message")])
    XCTAssertThrowsError(
      try ExpansionTransaction.perform(
        snippet, target: XCTUnwrap(harness.target), clipboard: harness, focus: harness,
        insertion: harness))
    XCTAssertNil(harness.inserted)
  }

  @MainActor func testCursorMetadataReachesInsertionWithoutMarkerText() throws {
    let harness = Harness()
    let snippet = SnippetRecord(
      name: "Caret", keyword: "gc", template: "git commit -m \"{cursor}\"")
    try ExpansionTransaction.perform(
      snippet, target: XCTUnwrap(harness.target),
      clipboard: harness, focus: harness, insertion: harness)
    XCTAssertEqual(harness.inserted, "git commit -m \"\"")
    XCTAssertEqual(harness.cursorOffset, 15)
  }
}
