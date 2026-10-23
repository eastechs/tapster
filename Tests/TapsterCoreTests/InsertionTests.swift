import AppKit
import XCTest

@testable import TapsterCore

final class InsertionTests: XCTestCase {
  @MainActor final class Focus: ExpansionFocus {
    var value: ExpansionTarget? = ExpansionTarget(processID: 1, focusID: "test")
    func currentTarget() -> ExpansionTarget? { value }
  }

  @MainActor func testClipboardRestoresAllRepresentationsWithoutReturnEvent() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let item = NSPasteboardItem()
    let html = Data("<b>Original</b>".utf8)
    item.setString("Original", forType: .string)
    item.setData(html, forType: .html)
    pasteboard.writeObjects([item])
    let focus = Focus()
    var keys: [Int64] = []
    let service = TextInsertionService(
      focus: focus, pasteboard: pasteboard, secureInput: { false },
      postEvent: {
        keys.append($0.getIntegerValueField(.keyboardEventKeycode))
        XCTAssertEqual(
          $0.getIntegerValueField(.eventSourceUserData), TextInsertionService.eventMarker)
      })
    defer { service.finish() }
    try service.replace(keyword: "gc", with: "Line one\nLine two", target: XCTUnwrap(focus.value))
    XCTAssertEqual(pasteboard.string(forType: .string), "Line one\nLine two")
    XCTAssertFalse(keys.contains(36))
    service.finish()
    XCTAssertEqual(pasteboard.string(forType: .string), "Original")
    XCTAssertEqual(pasteboard.data(forType: .html), html)
  }

  @MainActor func testNewUserCopyIsNeverOverwritten() throws {
    let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Original", forType: .string)
    let focus = Focus()
    let service = TextInsertionService(
      focus: focus, pasteboard: pasteboard, secureInput: { false }, postEvent: { _ in })
    defer { service.finish() }
    try service.replace(keyword: "x", with: "First\nSecond", target: XCTUnwrap(focus.value))
    pasteboard.clearContents()
    pasteboard.setString("New user copy", forType: .string)
    service.finish()
    XCTAssertEqual(pasteboard.string(forType: .string), "New user copy")
  }

  @MainActor func testChangedFocusAndSecureInputPreventInsertion() throws {
    let focus = Focus()
    let target = try XCTUnwrap(focus.value)
    var count = 0
    let service = TextInsertionService(
      focus: focus, secureInput: { false }, postEvent: { _ in count += 1 })
    focus.value = nil
    XCTAssertThrowsError(try service.replace(keyword: "gc", with: "Hello", target: target))
    XCTAssertEqual(count, 0)
    focus.value = target
    let secure = TextInsertionService(
      focus: focus, secureInput: { true }, postEvent: { _ in count += 1 })
    XCTAssertThrowsError(try secure.replace(keyword: "gc", with: "Hello", target: target))
    XCTAssertEqual(count, 0)
  }
}
