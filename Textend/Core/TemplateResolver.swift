import Foundation

enum TemplateError: LocalizedError, Equatable {
  case invalid(String)
  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}

struct ParsedTemplate {
  enum Part: Equatable {
    case literal(String)
    case placeholder(String)
    case cursor
  }
  var parts: [Part]
  var hasCursor: Bool { parts.contains(.cursor) }
  var names: [String] {
    var seen = Set<String>()
    return parts.compactMap {
      if case .placeholder(let name) = $0, seen.insert(name).inserted { return name }
      return nil
    }
  }
}

enum TemplateParser {
  static func parse(_ template: String) throws -> ParsedTemplate {
    let characters = Array(template)
    var parts: [ParsedTemplate.Part] = []
    var literal = ""
    var index = 0
    func flush() {
      if !literal.isEmpty {
        parts.append(.literal(literal))
        literal = ""
      }
    }
    while index < characters.count {
      let character = characters[index]
      if character == "{" || character == "}" {
        if index + 1 < characters.count, characters[index + 1] == character {
          literal.append(character)
          index += 2
          continue
        }
        guard character == "{" else {
          throw TemplateError.invalid("Unmatched }. Use }} for a literal closing brace.")
        }
        flush()
        index += 1
        var name = ""
        while index < characters.count, characters[index] != "}" {
          name.append(characters[index])
          index += 1
        }
        guard index < characters.count else {
          throw TemplateError.invalid("Unclosed placeholder. Use {{ for a literal opening brace.")
        }
        guard isValidName(name) else {
          throw TemplateError.invalid(
            "Placeholder names must start with a letter or underscore and contain only letters, numbers, or underscores."
          )
        }
        if name == "cursor" {
          guard !parts.contains(.cursor) else {
            throw TemplateError.invalid("Use only one {cursor} marker per template.")
          }
          parts.append(.cursor)
        } else {
          parts.append(.placeholder(name))
        }
        index += 1
      } else {
        literal.append(character)
        index += 1
      }
    }
    flush()
    return ParsedTemplate(parts: parts)
  }

  static func isValidName(_ name: String) -> Bool {
    guard let first = name.first, first == "_" || first.isLetter else { return false }
    return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
  }
}

enum TemplateResolver {
  static func resolve(
    _ snippet: SnippetRecord, clipboard: String?, date: Date = Date(), timeZone: TimeZone = .current
  ) throws -> String {
    try resolveExpansion(snippet, clipboard: clipboard, date: date, timeZone: timeZone).text
  }

  static func resolveExpansion(
    _ snippet: SnippetRecord, clipboard: String?, date: Date = Date(), timeZone: TimeZone = .current
  ) throws -> ResolvedExpansion {
    let parsed = try TemplateParser.parse(snippet.template)
    try validateCursorMapping(snippet, parsed: parsed)
    var resolved: [String: String] = [:]
    for name in parsed.names {
      guard let definition = snippet.placeholders.first(where: { $0.name == name }) else {
        throw TemplateError.invalid("Choose a source for {\(name)}.")
      }
      switch definition.source {
      case .clipboard:
        guard let clipboard, !clipboard.isEmpty else {
          throw TemplateError.invalid("The clipboard has no text. Your keyword was left unchanged.")
        }
        resolved[name] = clipboard
      case .dateTime:
        guard !definition.dateFormat.isEmpty else {
          throw TemplateError.invalid("Enter a date format for {\(name)}.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = definition.dateFormat
        resolved[name] = formatter.string(from: date)
      }
    }
    var text = ""
    var cursor: Int?
    for part in parsed.parts {
      switch part {
      case .literal(let value): text += value
      case .placeholder(let name): text += resolved[name] ?? ""
      case .cursor: cursor = text.utf16.count
      }
    }
    let result = ResolvedExpansion(text: text, cursorUTF16Offset: cursor)
    if cursor != nil, result.cursorIndex == nil {
      throw TemplateError.invalid(
        "Place {cursor} between complete characters, not inside an emoji or accented character.")
    }
    return result
  }

  static func validateCursorMapping(_ snippet: SnippetRecord, parsed: ParsedTemplate) throws {
    if parsed.hasCursor && snippet.placeholders.contains(where: { $0.name == "cursor" }) {
      throw TemplateError.invalid(
        "{cursor} is reserved for caret placement. Rename your existing cursor placeholder, or remove its mapping to use the caret marker."
      )
    }
  }
}

struct ResolvedExpansion: Equatable {
  var text: String
  var cursorUTF16Offset: Int?

  var cursorIndex: String.Index? {
    guard let offset = cursorUTF16Offset, offset >= 0, offset <= text.utf16.count else {
      return nil
    }
    let index = String.Index(utf16Offset: offset, in: text)
    return index == text.endIndex || text.indices.contains(index) ? index : nil
  }
}
