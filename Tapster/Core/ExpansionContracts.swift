import Foundation

struct ExpansionTarget: Equatable {
  var processID: Int32
  var focusID: String
}

@MainActor protocol ExpansionClipboard {
  func readText() -> String?
}

@MainActor protocol ExpansionFocus {
  func currentTarget() -> ExpansionTarget?
  func selectionRange() -> CFRange?
  func text(in range: CFRange) -> String?
  func moveCaret(to location: Int) -> Bool
}

extension ExpansionFocus {
  func selectionRange() -> CFRange? { nil }
  func text(in range: CFRange) -> String? { nil }
  func moveCaret(to location: Int) -> Bool { false }
}

@MainActor protocol ExpansionInsertion {
  func replace(keyword: String, with text: String, target: ExpansionTarget, cursorUTF16Offset: Int?)
    throws
}

/// Values are resolved before any destructive operation; focus is checked again after resolution.
@MainActor enum ExpansionTransaction {
  static func perform(
    _ snippet: SnippetRecord, target: ExpansionTarget,
    clipboard: ExpansionClipboard, focus: ExpansionFocus,
    insertion: ExpansionInsertion, date: Date = Date()
  ) throws {
    guard focus.currentTarget() == target else {
      throw TemplateError.invalid("Expansion cancelled because focus changed.")
    }
    let names = try TemplateParser.parse(snippet.template).names
    let needsClipboard = snippet.placeholders.contains {
      $0.source == .clipboard && names.contains($0.name)
    }
    let expansion = try TemplateResolver.resolveExpansion(
      snippet, clipboard: needsClipboard ? clipboard.readText() : nil, date: date)
    guard focus.currentTarget() == target else {
      throw TemplateError.invalid("Expansion cancelled because focus changed.")
    }
    try insertion.replace(
      keyword: snippet.keyword, with: expansion.text, target: target,
      cursorUTF16Offset: expansion.cursorUTF16Offset)
  }
}
