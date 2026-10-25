import XCTest

@testable import TextendCore

final class TemplateTests: XCTestCase {
  func testCursorAtStartMiddleEndAndTrailingSpace() throws {
    for (template, text, offset) in [
      ("{cursor}hello", "hello", 0),
      ("something {cursor} something else", "something  something else", 10),
      ("git commit {cursor}", "git commit ", 11),
      ("{cursor}", "", 0),
    ] {
      let snippet = SnippetRecord(name: "Caret", template: template)
      XCTAssertNoThrow(try LibraryValidation.validate(snippet, among: []))
      XCTAssertEqual(
        try TemplateResolver.resolveExpansion(snippet, clipboard: nil),
        ResolvedExpansion(text: text, cursorUTF16Offset: offset))
      XCTAssertEqual(try TemplateResolver.resolve(snippet, clipboard: nil), text)
    }
    let plain = try TemplateResolver.resolveExpansion(
      SnippetRecord(name: "Plain", template: "git commit "), clipboard: nil)
    XCTAssertEqual(plain.text, "git commit ")
    XCTAssertNil(plain.cursorUTF16Offset)
  }

  func testCursorUsesResolvedUnicodeLengthAndNeverParsesClipboardMarkers() throws {
    let clipboard = "👩🏽‍💻 e\u{301} {cursor}"
    let snippet = SnippetRecord(
      name: "Unicode", template: "{value}\n{cursor}{value}",
      placeholders: [.init(name: "value")])
    let result = try TemplateResolver.resolveExpansion(snippet, clipboard: clipboard)
    XCTAssertEqual(result.text, "\(clipboard)\n\(clipboard)")
    XCTAssertEqual(result.cursorUTF16Offset, clipboard.utf16.count + 1)
    XCTAssertEqual(String(result.text[try XCTUnwrap(result.cursorIndex)...]), clipboard)
    let escaped = try TemplateResolver.resolveExpansion(
      SnippetRecord(name: "Literal", template: "{{cursor}}"), clipboard: nil)
    XCTAssertEqual(escaped.text, "{cursor}")
    XCTAssertNil(escaped.cursorUTF16Offset)
  }

  func testCursorValidationAndExistingMappingProtection() throws {
    let duplicate = SnippetRecord(name: "Two", template: "{cursor}hello{cursor}")
    XCTAssertThrowsError(try LibraryValidation.validate(duplicate, among: []))
    XCTAssertThrowsError(try TemplateResolver.resolveExpansion(duplicate, clipboard: nil))
    let legacy = SnippetRecord(
      name: "Legacy", template: "{cursor}",
      placeholders: [.init(name: "cursor")])
    XCTAssertThrowsError(try TemplateResolver.resolveExpansion(legacy, clipboard: "Keep me"))
    XCTAssertThrowsError(
      try LibraryValidation.validateImport(
        LibraryArchive(collections: [], snippets: [legacy]),
        existing: LibraryArchive(collections: [], snippets: [])))
    for text in ["e{cursor}\u{301}", "👩{cursor}\u{200D}💻"] {
      XCTAssertThrowsError(
        try TemplateResolver.resolveExpansion(
          SnippetRecord(name: "Split character", template: text), clipboard: nil))
    }
    XCTAssertEqual(try TemplateParser.parse("{cursor} {text}").names, ["text"])
  }

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
