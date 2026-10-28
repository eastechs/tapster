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
  // Shared editor/index representation. Compositions persist in their own entity.
  var blocks: [CompositionBlock]? = nil
  var isComposition: Bool { blocks != nil }
}

struct CollectionRecord: Codable, Equatable, Identifiable {
  var id = UUID()
  var name: String
  var sortOrder = 0
  var appBundleIDs: [String]? = nil  // nil means all apps; empty means unavailable.
}

struct LibraryArchive: Codable, Equatable {
  var version = 2
  var collections: [CollectionRecord]
  var snippets: [SnippetRecord]
  var compositions: [CompositionRecord] = []

  enum CodingKeys: String, CodingKey { case version, collections, snippets, compositions }
  init(
    version: Int = 2, collections: [CollectionRecord], snippets: [SnippetRecord],
    compositions: [CompositionRecord] = []
  ) {
    self.version = version
    self.collections = collections
    self.snippets = snippets
    self.compositions = compositions
  }
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decode(Int.self, forKey: .version)
    collections = try c.decode([CollectionRecord].self, forKey: .collections)
    snippets = try c.decode([SnippetRecord].self, forKey: .snippets)
    compositions = try c.decodeIfPresent([CompositionRecord].self, forKey: .compositions) ?? []
    if version == 1 && (!compositions.isEmpty || collections.contains { $0.appBundleIDs != nil }) {
      throw TemplateError.invalid("This backup contains newer features but declares version 1.")
    }
  }
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
    if snippet.isComposition { return }
    let parsed = try TemplateParser.parse(snippet.template)
    try TemplateResolver.validateCursorMapping(snippet, parsed: parsed)
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
    guard [1, 2].contains(archive.version) else {
      throw TemplateError.invalid("This backup version is not supported.")
    }
    let collections = existing.collections + archive.collections
    guard !archive.snippets.contains(where: \.isComposition) else {
      throw TemplateError.invalid("Compositions must be stored in the compositions section.")
    }
    let snippets =
      existing.snippets + existing.compositions.map(\.item)
      + archive.snippets + archive.compositions.map(\.item)
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
    let library = ExpansionLibrary(items: snippets, collections: collections)
    for collection in archive.collections { try library.validateCollection(collection) }
    for snippet in archive.snippets + archive.compositions.map(\.item) {
      try library.validateContent(snippet)
      try library.validateKeyword(snippet)
      if let id = snippet.collectionID, !collectionIDs.contains(id) {
        throw TemplateError.invalid("‘\(snippet.name)’ refers to a missing collection.")
      }
    }
  }
}
