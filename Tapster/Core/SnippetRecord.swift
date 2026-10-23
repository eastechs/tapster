import Foundation

enum PlaceholderSource: String, Codable, CaseIterable, Identifiable {
  case clipboard, dateTime
  var id: String { rawValue }
  var title: String { self == .clipboard ? "Clipboard" : "Date & Time" }
}

struct PlaceholderDefinition: Codable, Equatable, Identifiable {
  var id = UUID()
  var name: String
  var source: PlaceholderSource = .clipboard
  var dateFormat = "yyyy-MM-dd"
}

struct SnippetRecord: Codable, Equatable, Identifiable {
  var id = UUID()
  var name = ""
  var keyword = ""
  var template = ""
  var collectionID: UUID?
  var isFavorite = false
  var isEnabled = true
  var placeholders: [PlaceholderDefinition] = []
  var createdAt = Date()
  var updatedAt = Date()
}

struct CollectionRecord: Codable, Equatable, Identifiable {
  var id = UUID()
  var name: String
  var sortOrder = 0
}

struct LibraryArchive: Codable, Equatable {
  var version = 1
  var collections: [CollectionRecord]
  var snippets: [SnippetRecord]
}

enum LibraryValidation {
  static func validate(_ snippet: SnippetRecord, among others: [SnippetRecord]) throws {
    guard !snippet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TemplateError.invalid("Give this snippet a name.")
    }
    if !snippet.keyword.isEmpty {
      guard snippet.keyword.count <= 64,
        !snippet.keyword.contains(where: {
          $0.isWhitespace || $0.isNewline
            || $0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        })
      else {
        throw TemplateError.invalid(
          "Keywords must contain 1–64 characters without whitespace or control characters.")
      }
      guard !others.contains(where: { $0.id != snippet.id && $0.keyword == snippet.keyword }) else {
        throw TemplateError.invalid("The keyword ‘\(snippet.keyword)’ is already in use.")
      }
    }
    let parsed = try TemplateParser.parse(snippet.template)
    guard !snippet.template.isEmpty else { throw TemplateError.invalid("Add some template text.") }
    guard Set(snippet.placeholders.map(\.name)).count == snippet.placeholders.count,
      Set(snippet.placeholders.map(\.id)).count == snippet.placeholders.count
    else {
      throw TemplateError.invalid("Placeholder definitions must have unique names and identifiers.")
    }
    for name in parsed.names {
      guard let mapping = snippet.placeholders.first(where: { $0.name == name }) else {
        throw TemplateError.invalid("Choose a source for {\(name)}.")
      }
      if mapping.source == .dateTime
        && mapping.dateFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        throw TemplateError.invalid("Enter a date format for {\(name)}.")
      }
    }
  }

  static func validateImport(_ archive: LibraryArchive, existing: LibraryArchive) throws {
    guard archive.version == 1 else {
      throw TemplateError.invalid("This backup version is not supported.")
    }
    let collections = existing.collections + archive.collections
    let snippets = existing.snippets + archive.snippets
    guard Set(collections.map(\.id)).count == collections.count,
      Set(snippets.map(\.id)).count == snippets.count
    else {
      throw TemplateError.invalid(
        "This backup contains identifiers that already exist. Import into an empty library or use a different backup."
      )
    }
    let collectionIDs = Set(collections.map(\.id))
    for collection in archive.collections
    where collection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw TemplateError.invalid("A collection in this backup has no name (\(collection.id)).")
    }
    for snippet in archive.snippets {
      try validate(snippet, among: snippets)
      if let id = snippet.collectionID, !collectionIDs.contains(id) {
        throw TemplateError.invalid("‘\(snippet.name)’ refers to a missing collection.")
      }
    }
  }
}
