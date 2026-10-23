import XCTest

@testable import TapsterCore

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
}
