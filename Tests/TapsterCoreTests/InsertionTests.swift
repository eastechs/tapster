import AppKit
import XCTest

@testable import TapsterCore

final class InsertionTests: XCTestCase {
  @MainActor final class Focus: ExpansionFocus {
    var value: ExpansionTarget? = ExpansionTarget(processID: 1, focusID: "test")
    var range: CFRange?
    var fieldText: String?
    var moves: [Int] = []
    var acceptsCaretMove = true
    func currentTarget() -> ExpansionTarget? { value }
    func selectionRange() -> CFRange? { range }
    func text(in range: CFRange) -> String? {
      guard let text = fieldText as NSString?, range.location >= 0,
        range.location + range.length <= text.length
      else { return nil }
      return text.substring(with: NSRange(location: range.location, length: range.length))
    }
    func moveCaret(to location: Int) -> Bool {
      guard acceptsCaretMove else { return false }
      moves.append(location)
      range = CFRange(location: location, length: 0)
      return true
    }
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

  @MainActor func testCursorWaitsForInsertionThenUsesAbsoluteUTF16Position() throws {
    let h = CursorHarness()
    defer { h.stop() }
    let text = "👩🏽‍💻\nhello"
    h.focus.range = CFRange(location: 12, length: 0)
    try h.service.replace(
      keyword: "gc", with: text, target: h.target,
      cursorUTF16Offset: "👩🏽‍💻\n".utf16.count)
    XCTAssertEqual(h.pasteboard.string(forType: .string), text)
    h.tick()
    XCTAssertTrue(h.focus.moves.isEmpty, "Pasting may not have been consumed yet.")
    h.focus.range = CFRange(location: 10 + text.utf16.count, length: 0)
    h.focus.fieldText = String(repeating: " ", count: 10) + text
    h.tick()
    XCTAssertEqual(h.focus.moves, [10 + "👩🏽‍💻\n".utf16.count])
    XCTAssertFalse(h.keys.contains(123), "AX movement needs no arrow-key fallback.")
    XCTAssertFalse(h.keys.contains(36))
    h.service.finish()
    XCTAssertEqual(h.pasteboard.string(forType: .string), "Original clipboard")
  }

  @MainActor func testCursorFallbackCountsCompleteCharactersAndTagsEvents() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.acceptsCaretMove = false
    let text = "A👩🏽‍💻e\u{301}"
    try h.service.replace(keyword: "gc", with: text, target: h.target, cursorUTF16Offset: 1)
    h.focus.range = CFRange(location: text.utf16.count, length: 0)
    h.focus.fieldText = text
    h.tick()
    XCTAssertEqual(h.keys.filter { $0 == 123 }.count, 4, "Two complete characters, down/up each.")
    XCTAssertTrue(h.markers.allSatisfy { $0 == TextInsertionService.eventMarker })
  }

  @MainActor func testCursorCancellationRejectsStaleCallbacksAndNewTargets() throws {
    for reason in ["input", "focus", "secure", "finish"] {
      let h = CursorHarness()
      defer { h.stop() }
      try h.service.replace(keyword: "gc", with: "hello", target: h.target, cursorUTF16Offset: 2)
      h.focus.range = CFRange(location: 5, length: 0)
      h.focus.fieldText = "hello"
      switch reason {
      case "input": h.service.cancelCursorPlacement()
      case "focus": h.focus.value = ExpansionTarget(processID: 2, focusID: "other")
      case "secure": h.secure = true
      default: h.service.finish()
      }
      let keyCount = h.keys.count
      h.tick()
      XCTAssertTrue(h.focus.moves.isEmpty, reason)
      XCTAssertEqual(h.keys.count, keyCount, reason)
    }
  }

  @MainActor func testCursorTimeoutReportsWithoutMovingAndPreservesNewCopy() throws {
    let h = CursorHarness()
    defer { h.stop() }
    try h.service.replace(keyword: "gc", with: "A\nB", target: h.target, cursorUTF16Offset: 1)
    h.focus.range = CFRange(location: 20, length: 0)  // Host added unexpected text.
    h.pasteboard.clearContents()
    h.pasteboard.setString("New copy", forType: .string)
    for _ in 0..<30 { h.tick() }
    XCTAssertEqual(h.failures.count, 1)
    XCTAssertTrue(h.focus.moves.isEmpty)
    XCTAssertFalse(h.keys.contains(123))
    h.service.finish()
    XCTAssertEqual(h.pasteboard.string(forType: .string), "New copy")
  }

  @MainActor func testEqualLengthReplacementRequiresConfirmedText() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.fieldText = "gc"
    try h.service.replace(keyword: "gc", with: "ab", target: h.target, cursorUTF16Offset: 1)
    h.tick()
    XCTAssertTrue(h.focus.moves.isEmpty)
    h.focus.fieldText = "ab"
    h.tick()
    XCTAssertEqual(h.focus.moves, [1])
  }

  @MainActor func testLongCursorMoveUsesAXWithoutFloodingHostWithArrows() throws {
    for acceptsAX in [true, false] {
      let h = CursorHarness()
      defer { h.stop() }
      h.focus.acceptsCaretMove = acceptsAX
      let text = String(repeating: "x", count: 300)
      try h.service.replace(keyword: "gc", with: text, target: h.target, cursorUTF16Offset: 0)
      h.focus.range = CFRange(location: 300, length: 0)
      h.focus.fieldText = text
      h.tick()
      XCTAssertEqual(h.focus.moves, acceptsAX ? [0] : [])
      XCTAssertEqual(h.failures.count, acceptsAX ? 0 : 1)
      XCTAssertFalse(h.keys.contains(123))
    }
  }

  @MainActor func testEndMarkerNeedsNoMoveAndInvalidMarkerCannotDeleteKeyword() throws {
    let h = CursorHarness()
    defer { h.stop() }
    h.focus.range = nil
    try h.service.replace(
      keyword: "gc", with: "git commit ", target: h.target, cursorUTF16Offset: 11)
    XCTAssertFalse(h.jobs.contains { $0.0 == 0.01 })
    h.service.finish()
    let count = h.keys.count
    for offset in [-1, 1, 4] {
      XCTAssertThrowsError(
        try h.service.replace(
          keyword: "gc", with: "😀", target: h.target,
          cursorUTF16Offset: offset))
    }
    XCTAssertThrowsError(
      try h.service.replace(
        keyword: "gc", with: "hello", target: h.target,
        cursorUTF16Offset: 2))
    XCTAssertEqual(h.keys.count, count)
  }
}

@MainActor private final class CursorHarness {
  let focus = InsertionTests.Focus()
  let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
  var target: ExpansionTarget { focus.value! }
  var secure = false
  var keys: [Int64] = []
  var markers: [Int64] = []
  var jobs: [(TimeInterval, DispatchWorkItem)] = []
  var failures: [String] = []
  lazy var service = TextInsertionService(
    focus: focus, pasteboard: pasteboard,
    secureInput: { [unowned self] in secure },
    postEvent: { [unowned self] event in
      keys.append(event.getIntegerValueField(.keyboardEventKeycode))
      markers.append(event.getIntegerValueField(.eventSourceUserData))
    }, schedule: { [unowned self] delay, work in jobs.append((delay, work)) },
    cursorFailure: { [unowned self] in failures.append($0) })

  init() {
    focus.range = CFRange(location: 2, length: 0)
    pasteboard.setString("Original clipboard", forType: .string)
  }
  func tick() {
    guard let index = jobs.firstIndex(where: { $0.0 == 0.01 }) else {
      XCTFail("Missing cursor callback")
      return
    }
    jobs.remove(at: index).1.perform()
  }
  func stop() {
    service.finish()
    jobs.removeAll()
    pasteboard.releaseGlobally()
  }
}
