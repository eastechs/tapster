import XCTest

@testable import TapsterCore

final class TemplateTests: XCTestCase {
  func testClipboardValuesAreLiteralAndRepeatedConsistently() throws {
    let snippet = SnippetRecord(
      name: "Test", template: "{value} / {value}", placeholders: [.init(name: "value")])
    XCTAssertEqual(
      try TemplateResolver.resolve(snippet, clipboard: "{today}\n💐"), "{today}\n💐 / {today}\n💐")
  }

  func testBraceEscapingAndNames() throws {
    let result = try TemplateParser.parse("{{literal}} {{{name}}} {name}")
    XCTAssertEqual(result.names, ["name"])
    let snippet = SnippetRecord(
      name: "Escapes", template: "{{literal}} {{{name}}}", placeholders: [.init(name: "name")])
    XCTAssertEqual(try TemplateResolver.resolve(snippet, clipboard: "Dave"), "{literal} {Dave}")
  }

  func testMalformedTemplatesAndMissingMappings() {
    for value in ["{", "}", "{bad name}", "{3name}", "{nested{name}}", "{}"] {
      XCTAssertThrowsError(try TemplateParser.parse(value), value)
    }
    XCTAssertThrowsError(
      try TemplateResolver.resolve(
        SnippetRecord(name: "Missing", template: "{value}"), clipboard: "hi"))
  }

  func testEmptyClipboardOnlyBlocksTemplatesThatNeedIt() throws {
    let dynamic = SnippetRecord(
      name: "Dynamic", template: "{text}", placeholders: [.init(name: "text")])
    XCTAssertThrowsError(try TemplateResolver.resolve(dynamic, clipboard: nil))
    XCTAssertThrowsError(try TemplateResolver.resolve(dynamic, clipboard: ""))
    XCTAssertEqual(
      try TemplateResolver.resolve(
        SnippetRecord(name: "Static", template: "hello"), clipboard: nil), "hello")
  }

  func testDateUsesInjectedClockAndTimeZone() throws {
    let snippet = SnippetRecord(
      name: "Date", template: "{date}", placeholders: [.init(name: "date", source: .dateTime)])
    XCTAssertEqual(
      try TemplateResolver.resolve(
        snippet, clipboard: nil, date: Date(timeIntervalSince1970: 0),
        timeZone: TimeZone(secondsFromGMT: 0)!), "1970-01-01")
  }

  func testPrefixOverlapAllowedButExactDuplicatesRejected() throws {
    let first = SnippetRecord(name: "Commit", keyword: "gc", template: "hello")
    let next = SnippetRecord(name: "Checkout", keyword: "gco", template: "world")
    XCTAssertNoThrow(try LibraryValidation.validate(next, among: [first]))
    var duplicate = next
    duplicate.keyword = "gc"
    XCTAssertThrowsError(try LibraryValidation.validate(duplicate, among: [first]))
  }
}
