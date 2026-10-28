import XCTest

@testable import TextendCore

final class MatcherTests: XCTestCase {
  private func matcher(_ keywords: [String]) -> TriggerMatcher {
    var matcher = TriggerMatcher()
    matcher.update(keywords.map { SnippetRecord(name: $0, keyword: $0, template: $0) })
    return matcher
  }

  func testImmediateMatchAndNoRecursionInsideWord() throws {
    var sut = matcher(["gc"])
    XCTAssertNil(sut.input("g", now: 0))
    let match = try XCTUnwrap(sut.input("c", now: 0.1))
    XCTAssertNil(match.deadline)
    XCTAssertEqual(sut.take(match, now: 0.1)?.keyword, "gc")
    XCTAssertNil(sut.input("g", now: 0.2))
    XCTAssertNil(sut.input("c", now: 0.3))
  }

  func testShortPrefixWaitsAndStaleTimerCannotExpandLongerMatch() throws {
    var sut = matcher(["gc", "gco"])
    _ = sut.input("g", now: 0)
    let short = try XCTUnwrap(sut.input("c", now: 0.1))
    XCTAssertEqual(short.deadline, 0.35)
    XCTAssertNil(sut.take(short, now: 0.34))
    let long = try XCTUnwrap(sut.input("o", now: 0.2))
    XCTAssertNil(long.deadline)
    XCTAssertNil(sut.take(short, now: 2))
    XCTAssertEqual(sut.take(long, now: 0.2)?.keyword, "gco")
  }

  func testDebounceExpiresWithConfigurableDelay() throws {
    var sut = matcher(["gc", "gco"])
    sut.delay = 0.75
    _ = sut.input("g", now: 0)
    let match = try XCTUnwrap(sut.input("c", now: 1))
    XCTAssertNil(sut.take(match, now: 1.749))
    XCTAssertEqual(sut.take(match, now: 1.75)?.keyword, "gc")
  }

  func testIncompleteAndUnrelatedInputCancelShortMatch() throws {
    for continuation in ["o", "x", " "] {
      var sut = matcher(["gc", "gcommit"])
      _ = sut.input("g", now: 0)
      let short = try XCTUnwrap(sut.input("c", now: 0))
      XCTAssertNil(sut.input(continuation, now: 0.1))
      XCTAssertNil(sut.take(short, now: 1))
    }
  }

  func testNestedPrefixesAndResetInvalidation() throws {
    var sut = matcher(["g", "gc", "gco"])
    let first = try XCTUnwrap(sut.input("g", now: 0))
    let second = try XCTUnwrap(sut.input("c", now: 0.1))
    XCTAssertNotNil(second.deadline)
    XCTAssertNil(sut.take(first, now: 2))
    sut.reset()
    XCTAssertNil(sut.take(second, now: 2))
  }

  func testNoEmbeddedWordMatchAndMultiCharacterInputCancels() {
    var sut = matcher(["gc"])
    for char in "magicgc" { XCTAssertNil(sut.input(String(char), now: 0)) }
    _ = sut.input(" ", now: 0)
    XCTAssertNil(sut.input("gc", now: 0))
  }

  func testUpdatingIndexCancelsPendingAndDisabledSnippetsAreIgnored() throws {
    var sut = matcher(["gc", "gco"])
    _ = sut.input("g", now: 0)
    let match = try XCTUnwrap(sut.input("c", now: 0))
    sut.update([SnippetRecord(name: "Disabled", keyword: "gc", template: "x", isEnabled: false)])
    XCTAssertNil(sut.take(match, now: 2))
    XCTAssertNil(sut.input("g", now: 2))
    XCTAssertNil(sut.input("c", now: 2))
  }

  func testCorrectingATypoAnywhereInAKeywordStillExpands() throws {
    for keyword in ["gc", "hello", ";sig"] {
      for position in keyword.indices {
        for typo in ["x", "!", " ", "é"] {
          var sut = matcher([keyword])
          for character in keyword[..<position] {
            XCTAssertNil(sut.input(String(character), now: 0))
          }
          XCTAssertNil(sut.input(typo, now: 0))
          sut.backspace()
          var match: TriggerMatch?
          for character in keyword[position...] {
            match = sut.input(String(character), now: 0.1)
          }
          XCTAssertEqual(sut.take(try XCTUnwrap(match), now: 0.1)?.keyword, keyword)
        }
      }
    }
  }

  func testBackspacingAValidPrefixAndRetypingStillExpands() throws {
    var sut = matcher(["hello"])
    for character in "hell" { _ = sut.input(String(character), now: 0) }
    sut.backspace()
    XCTAssertNil(sut.input("l", now: 0.1))
    let match = try XCTUnwrap(sut.input("o", now: 0.2))
    XCTAssertEqual(sut.take(match, now: 0.2)?.keyword, "hello")
  }

  func testAllMistypedCharactersMustBeDeletedBeforeMatchingResumes() throws {
    for deleteCount in [1, 2] {
      var sut = matcher(["hello"])
      for character in "hexy" { _ = sut.input(String(character), now: 0) }
      for _ in 0..<deleteCount { sut.backspace() }
      var match: TriggerMatch?
      for character in "llo" { match = sut.input(String(character), now: 0.1) }
      if deleteCount == 2 {
        XCTAssertEqual(sut.take(try XCTUnwrap(match), now: 0.1)?.keyword, "hello")
      } else {
        XCTAssertNil(match)
      }
    }
  }

  func testDeletingAWordBoundaryDoesNotAllowEmbeddedKeywords() {
    var sut = matcher(["hello"])
    for character in "word " { _ = sut.input(String(character), now: 0) }
    sut.backspace()
    for character in "hello" { XCTAssertNil(sut.input(String(character), now: 0.1)) }
  }

  func testBackspacePreservesKnownWordInterior() {
    var sut = matcher(["gc"])
    sut.reset(atBoundary: false)
    _ = sut.input("x", now: 0)
    sut.backspace()
    XCTAssertNil(sut.input("g", now: 0.1))
    XCTAssertNil(sut.input("c", now: 0.2))
  }

  func testBackspaceCancelsPendingMatchAndRetypingStartsANewDelay() throws {
    var sut = matcher(["gc", "gco"])
    _ = sut.input("g", now: 0)
    let original = try XCTUnwrap(sut.input("c", now: 0.1))
    sut.backspace()
    XCTAssertNil(sut.pending)
    let corrected = try XCTUnwrap(sut.input("c", now: 0.2))
    XCTAssertNil(sut.take(original, now: 1))
    XCTAssertNil(sut.take(corrected, now: 0.44))
    XCTAssertEqual(sut.take(corrected, now: 0.45)?.keyword, "gc")
  }

  func testDeletingATypoDoesNotReviveAnOldPendingMatch() throws {
    var sut = matcher(["gc", "gco"])
    _ = sut.input("g", now: 0)
    let original = try XCTUnwrap(sut.input("c", now: 0.1))
    _ = sut.input("x", now: 0.2)
    sut.backspace()
    XCTAssertNil(sut.pending)
    XCTAssertNil(sut.take(original, now: 1))
    let corrected = try XCTUnwrap(sut.input("o", now: 1))
    XCTAssertEqual(sut.take(corrected, now: 1)?.keyword, "gco")
  }

  func testBackspacingBeyondObservedHistoryWaitsForANewBoundary() throws {
    var sut = matcher(["gc"])
    for character in "longword" { _ = sut.input(String(character), now: 0) }
    for _ in 0..<7 { sut.backspace() }
    // The host still contains "l". Exhausting history must not invent a word start.
    XCTAssertNil(sut.input("g", now: 0.1))
    XCTAssertNil(sut.input("c", now: 0.2))
    _ = sut.input(" ", now: 0.3)
    _ = sut.input("g", now: 0.4)
    XCTAssertNotNil(sut.input("c", now: 0.5))
  }

  func testResetIndexUpdateAndUnsupportedInputClearCorrectionHistory() {
    for interruption in ["reset", "update", "composition"] {
      var sut = matcher(["gc"])
      _ = sut.input("g", now: 0)
      _ = sut.input("x", now: 0)
      switch interruption {
      case "reset": sut.reset()
      case "update": sut.update([SnippetRecord(name: "Git", keyword: "gc", template: "git")])
      default: _ = sut.input("ab", now: 0)
      }
      sut.backspace()
      XCTAssertNil(sut.input("c", now: 0.1), interruption)
    }
  }

  func testExpansionClearsCorrectionHistory() throws {
    var sut = matcher(["gc"])
    _ = sut.input("g", now: 0)
    let match = try XCTUnwrap(sut.input("c", now: 0))
    XCTAssertNotNil(sut.take(match, now: 0))
    sut.backspace()
    XCTAssertNil(sut.input("c", now: 0.1))
  }
}
