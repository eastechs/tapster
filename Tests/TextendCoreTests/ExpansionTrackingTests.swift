import XCTest

@testable import TextendCore

final class ExpansionTrackingTests: XCTestCase {
  private let target = ExpansionTarget(processID: 1, focusID: "field")

  private func tracker() -> ExpansionTracking {
    var tracking = ExpansionTracking()
    tracking.matcher.update([
      SnippetRecord(name: "Greeting", keyword: "hello", template: "Hello there!"),
      SnippetRecord(name: "Short", keyword: "gc", template: "git commit"),
      SnippetRecord(name: "Long", keyword: "gco", template: "git checkout"),
    ])
    return tracking
  }

  func testMissingCaretAndBoundaryStillMatchTypedKeyword() throws {
    var tracking = tracker()
    var match: TriggerMatch?
    for character in "hello" {
      match = tracking.input(
        String(character), target: target, selection: nil, startsAtBoundary: nil, now: 0)
    }
    XCTAssertEqual(try XCTUnwrap(match).snippet.keyword, "hello")
    XCTAssertEqual(tracking.readiness(selection: nil), .ready)
  }

  func testDelayedAccessibilityDoesNotResetTheTypedRun() throws {
    var tracking = tracker()
    var match: TriggerMatch?
    for character in "hello" {
      match = tracking.input(
        String(character), target: target, selection: CFRange(location: 10, length: 0),
        startsAtBoundary: true, now: 0)
    }
    XCTAssertNotNil(match)
    XCTAssertEqual(tracking.readiness(selection: CFRange(location: 12, length: 0)), .ready)
    XCTAssertEqual(tracking.readiness(selection: CFRange(location: 15, length: 0)), .ready)
    XCTAssertEqual(tracking.readiness(selection: CFRange(location: 16, length: 0)), .ready)
  }

  func testMissingBoundaryAtReadableCaretDoesNotDisableMatching() {
    var tracking = tracker()
    for character in "hello" {
      _ = tracking.input(
        String(character), target: target, selection: CFRange(location: 4, length: 0),
        startsAtBoundary: nil, now: 0)
    }
    XCTAssertEqual(tracking.matcher.pending?.snippet.keyword, "hello")
  }

  func testKnownWordInteriorAndObservedWordInteriorDoNotMatch() {
    for (text, boundary) in [("hello", false), ("shellhello", true)] {
      var tracking = tracker()
      for character in text {
        XCTAssertNil(
          tracking.input(
            String(character), target: target, selection: nil,
            startsAtBoundary: boundary, now: 0))
      }
      _ = tracking.input(" ", target: target, selection: nil, startsAtBoundary: nil, now: 0)
      for character in "hello" {
        _ = tracking.input(
          String(character), target: target, selection: nil, startsAtBoundary: nil, now: 0)
      }
      XCTAssertEqual(tracking.matcher.pending?.snippet.keyword, "hello")
    }
  }

  func testSelectionAndFocusChangesInvalidatePendingMatches() throws {
    for change in ["selection", "focus", "reset"] {
      var tracking = tracker()
      _ = tracking.input("g", target: target, selection: nil, startsAtBoundary: nil, now: 0)
      let match = try XCTUnwrap(
        tracking.input(
          "c", target: target, selection: nil, startsAtBoundary: nil, now: 0))
      switch change {
      case "selection":
        XCTAssertEqual(tracking.readiness(selection: CFRange(location: 0, length: 2)), .cancelled)
        _ = tracking.input(
          "o", target: target, selection: CFRange(location: 0, length: 2),
          startsAtBoundary: nil, now: 0)
      case "focus":
        _ = tracking.input(
          "o", target: ExpansionTarget(processID: 1, focusID: "other"), selection: nil,
          startsAtBoundary: nil, now: 0)
      default: tracking.reset()
      }
      XCTAssertNil(tracking.matcher.take(match, now: 1), change)
    }
  }

  func testRangeAvailabilityCanChangeDuringTyping() {
    var tracking = tracker()
    _ = tracking.input(
      "g", target: target, selection: nil, startsAtBoundary: nil, now: 0)
    XCTAssertNotNil(
      tracking.input(
        "c", target: target, selection: CFRange(location: 40, length: 0),
        startsAtBoundary: false, now: 0))
    XCTAssertEqual(tracking.readiness(selection: CFRange(location: 41, length: 0)), .ready)
    tracking.reset()
    _ = tracking.input(
      "g", target: target, selection: CFRange(location: 0, length: 0),
      startsAtBoundary: true, now: 0)
    XCTAssertNotNil(
      tracking.input(
        "c", target: target, selection: nil, startsAtBoundary: nil, now: 0))
    XCTAssertEqual(tracking.readiness(selection: nil), .ready)
  }

  func testConfirmedKeywordSurvivesEarlierAutocorrectionButChangedTextDoesNot() {
    var tracking = tracker()
    for character in "teh hello" {
      _ = tracking.input(
        String(character), target: target, selection: CFRange(location: 0, length: 0),
        startsAtBoundary: true, now: 0)
    }
    let correctedCaret = CFRange(location: 12, length: 0)
    XCTAssertEqual(tracking.readiness(selection: correctedCaret, matchingKeyword: true), .ready)
    XCTAssertEqual(tracking.readiness(selection: correctedCaret, matchingKeyword: false), .waiting)
    XCTAssertEqual(
      tracking.readiness(selection: CFRange(location: 12, length: 2), matchingKeyword: true),
      .cancelled)
  }

  func testTypoCorrectionWorksWithMissingOrDelayedAccessibility() throws {
    for selection in [nil, CFRange(location: 10, length: 0)] {
      var tracking = tracker()
      for character in "hex" {
        _ = tracking.input(
          String(character), target: target, selection: selection,
          startsAtBoundary: nil, now: 0)
      }
      tracking.backspace(target: target, selection: selection)
      var match: TriggerMatch?
      for character in "llo" {
        match = tracking.input(
          String(character), target: target, selection: selection,
          startsAtBoundary: false, now: 0.1)
      }
      XCTAssertEqual(try XCTUnwrap(match).snippet.keyword, "hello")
    }
  }

  func testBackspaceWithSelectionOrChangedFocusDiscardsCorrectionHistory() {
    for change in ["selection", "focus", "reset"] {
      var tracking = tracker()
      for character in "hex" {
        _ = tracking.input(
          String(character), target: target, selection: nil, startsAtBoundary: nil, now: 0)
      }
      switch change {
      case "selection":
        tracking.backspace(target: target, selection: CFRange(location: 0, length: 3))
      case "focus":
        tracking.backspace(
          target: ExpansionTarget(processID: 2, focusID: "other"), selection: nil)
      default:
        tracking.reset()
        tracking.backspace(target: target, selection: nil)
      }
      for character in "llo" {
        XCTAssertNil(
          tracking.input(
            String(character), target: target, selection: nil,
            startsAtBoundary: nil, now: 0.1), change)
      }
    }
  }

  func testBackspaceInvalidatesPendingMatchEvenWhenItCannotTrackDeletion() throws {
    for selection in [nil, CFRange(location: 0, length: 2)] {
      var tracking = tracker()
      _ = tracking.input("g", target: target, selection: nil, startsAtBoundary: nil, now: 0)
      let match = try XCTUnwrap(
        tracking.input("c", target: target, selection: nil, startsAtBoundary: nil, now: 0))
      tracking.backspace(target: target, selection: selection)
      XCTAssertNil(tracking.matcher.pending)
      XCTAssertNil(tracking.matcher.take(match, now: 1))
    }
  }
}
