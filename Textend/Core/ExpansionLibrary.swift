import Foundation

/// Immutable saved values shared by automatic matching, manual insertion and validation.
struct ExpansionLibrary {
  var items: [SnippetRecord] = []
  var collections: [CollectionRecord] = []
  var errors: [UUID: String] = [:]

  // nil is unrestricted; empty is deliberately unavailable (including missing dependencies).
  func scope(of item: SnippetRecord) -> Set<String>? {
    var result: Set<String>?
    if let id = item.collectionID {
      guard let collection = collections.first(where: { $0.id == id }) else { return [] }
      guard (try? validateCollection(collection)) != nil else { return [] }
      result = collection.appBundleIDs.map(Set.init)
    }
    for block in item.blocks ?? [] {
      guard let id = block.snippetID else { continue }
      guard let source = items.first(where: { $0.id == id }), !source.isComposition else {
        return []
      }
      // Sources cannot be Compositions, so scope recursion is bounded to one level.
      if let sourceScope = scope(of: source) {
        result = result.map { $0.intersection(sourceScope) } ?? sourceScope
      }
    }
    return result
  }

  func allows(_ item: SnippetRecord, in bundleID: String?) -> Bool {
    guard let scope = scope(of: item) else { return true }
    return bundleID.map(scope.contains) ?? false
  }

  func scopeDescription(_ item: SnippetRecord) -> String {
    guard let scope = scope(of: item) else { return "All apps" }
    return scope.isEmpty
      ? "Unavailable: check collections and source snippets."
      : scope.sorted().joined(separator: ", ")
  }

  func validateCollection(_ collection: CollectionRecord) throws {
    guard !collection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TemplateError.invalid("Give this collection a name.")
    }
    if let ids = collection.appBundleIDs {
      guard !ids.isEmpty, Set(ids).count == ids.count,
        ids.allSatisfy({ !$0.isEmpty && !$0.contains(where: \.isWhitespace) })
      else {
        throw TemplateError.invalid("Choose at least one valid application for this collection.")
      }
    }
  }

  func validateContent(_ item: SnippetRecord) throws {
    if let error = errors[item.id] { throw TemplateError.invalid(error) }
    try LibraryValidation.validate(item, among: [item])
    guard let blocks = item.blocks else { return }
    guard !blocks.isEmpty, Set(blocks.map(\.id)).count == blocks.count else {
      throw TemplateError.invalid("Add blocks with unique identifiers to this Composition.")
    }
    var cursors = 0
    for block in blocks {
      if let id = block.snippetID {
        guard let snippet = items.first(where: { $0.id == id }), !snippet.isComposition else {
          throw TemplateError.invalid("A source snippet is missing. Replace or remove its block.")
        }
        if let error = errors[id] { throw TemplateError.invalid(error) }
        try LibraryValidation.validate(snippet, among: [snippet])
        if try TemplateParser.parse(snippet.template).hasCursor { cursors += 1 }
      }
    }
    guard cursors <= 1 else {
      throw TemplateError.invalid("Use only one {cursor} across all included snippet occurrences.")
    }
    guard blocks.contains(where: { $0.snippetID != nil || !$0.text.isEmpty }) else {
      throw TemplateError.invalid("Add some text or a source snippet.")
    }
  }

  func resolve(_ item: SnippetRecord, clipboard: String?, date: Date = Date()) throws
    -> ResolvedExpansion
  {
    try validateContent(item)
    guard let blocks = item.blocks else {
      return try TemplateResolver.resolveExpansion(item, clipboard: clipboard, date: date)
    }
    var text = ""
    var cursor: Int?
    for (index, block) in blocks.enumerated() {
      if let id = block.snippetID, let snippet = items.first(where: { $0.id == id }) {
        let value = try TemplateResolver.resolveExpansion(snippet, clipboard: clipboard, date: date)
        if let offset = value.cursorUTF16Offset { cursor = text.utf16.count + offset }
        text += value.text
      } else {
        text += block.text
      }
      if index < blocks.count - 1 { text += block.separator.text }
    }
    let result = ResolvedExpansion(text: text, cursorUTF16Offset: cursor)
    if cursor != nil && result.cursorIndex == nil {
      throw TemplateError.invalid(
        "The combined cursor position must be between complete characters.")
    }
    return result
  }

  func conflicts(for item: SnippetRecord) -> [SnippetRecord] {
    guard !item.keyword.isEmpty else { return [] }
    let own = scope(of: item)
    return items.filter { other in
      guard other.id != item.id, other.keyword == item.keyword else { return false }
      let theirs = scope(of: other)
      switch (own, theirs) {
      case (nil, nil): return true
      case (.some(let a), .some(let b)): return !a.isDisjoint(with: b)
      default: return false  // A scoped keyword deliberately overrides a global keyword.
      }
    }
  }

  func introducesConflict(
    _ item: SnippetRecord, with other: SnippetRecord, comparedTo old: ExpansionLibrary
  ) -> Bool {
    guard let oldItem = old.items.first(where: { $0.id == item.id }),
      let oldOther = old.items.first(where: { $0.id == other.id }),
      oldItem.keyword == item.keyword, oldOther.keyword == other.keyword,
      old.conflicts(for: oldItem).contains(where: { $0.id == other.id })
    else { return true }
    switch (scope(of: item), scope(of: other), old.scope(of: oldItem), old.scope(of: oldOther)) {
    case (nil, nil, nil, nil): return false
    case (.some(let a), .some(let b), .some(let oldA), .some(let oldB)):
      return !a.intersection(b).isSubset(of: oldA.intersection(oldB))
    default: return true
    }
  }

  func needsClipboard(_ item: SnippetRecord) -> Bool {
    if let blocks = item.blocks {
      return blocks.contains { block in
        guard let id = block.snippetID, let source = items.first(where: { $0.id == id }),
          !source.isComposition
        else { return false }
        return needsClipboard(source)
      }
    }
    let names = (try? TemplateParser.parse(item.template).names) ?? []
    return item.placeholders.contains { $0.source == .clipboard && names.contains($0.name) }
  }

  func validateKeyword(_ item: SnippetRecord) throws {
    let matches = conflicts(for: item)
    guard matches.isEmpty else {
      throw TemplateError.invalid(
        "The keyword ‘\(item.keyword)’ conflicts with \(matches.map(\.name).joined(separator: ", ")) in overlapping apps."
      )
    }
  }

  func automaticItems(in bundleID: String?) -> [SnippetRecord] {
    let enabled = items.filter {
      $0.isEnabled && !$0.keyword.isEmpty && allows($0, in: bundleID)
        && (try? validateContent($0)) != nil
    }
    return Dictionary(grouping: enabled, by: \.keyword).values.compactMap { group in
      let scoped = group.filter { scope(of: $0) != nil }
      let candidates = scoped.isEmpty ? group : scoped
      return candidates.count == 1 ? candidates[0] : nil
    }
  }

  func issue(for item: SnippetRecord) -> String? {
    do { try validateContent(item) } catch { return error.localizedDescription }
    if let scope = scope(of: item), scope.isEmpty { return scopeDescription(item) }
    let conflicts = conflicts(for: item).filter {
      $0.isEnabled && (try? validateContent($0)) != nil
    }
    if item.isEnabled && !conflicts.isEmpty {
      return
        "Expansion paused in overlapping apps: ‘\(item.keyword)’ is also used by \(conflicts.map(\.name).joined(separator: ", ")). Rename or clear a keyword."
    }
    return nil
  }

  func search(_ query: String, bundleID: String?, allApps: Bool) -> [SnippetRecord] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return items.filter { item in
      guard allApps || allows(item, in: bundleID) else { return false }
      let sourceText = (item.blocks ?? []).map { block in
        block.snippetID.flatMap { id in items.first { $0.id == id }?.template } ?? block.text
      }.joined(separator: " ")
      let collection = collections.first { $0.id == item.collectionID }?.name ?? ""
      return query.isEmpty
        || [item.name, item.keyword, item.template, collection, sourceText].contains {
          $0.localizedCaseInsensitiveContains(query)
        }
    }.sorted {
      if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
      return SnippetSortOrder.name.precedes($0, $1)
    }
  }
}
