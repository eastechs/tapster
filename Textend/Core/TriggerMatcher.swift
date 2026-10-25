import Foundation

struct TriggerMatch: Equatable {
  var snippet: SnippetRecord
  var generation: UInt64
  var deadline: TimeInterval?
}

/// Pure state machine. The platform coordinator owns scheduling and focus checks.
struct TriggerMatcher {
  private(set) var generation: UInt64 = 0
  private(set) var pending: TriggerMatch?
  private var snippets: [SnippetRecord] = []
  private var buffer = ""
  private var atBoundary = true
  private var longestKeyword = 0
  var delay: TimeInterval = 0.25

  mutating func update(_ snippets: [SnippetRecord]) {
    let groups = Dictionary(grouping: snippets, by: \.keyword)
    self.snippets = snippets.filter {
      $0.isEnabled && !$0.keyword.isEmpty && groups[$0.keyword]?.count == 1
    }
    longestKeyword = self.snippets.map { $0.keyword.count }.max() ?? 0
    reset()
  }

  mutating func reset(atBoundary: Bool = true) {
    generation &+= 1
    buffer = ""
    pending = nil
    self.atBoundary = atBoundary
  }

  mutating func input(_ text: String, now: TimeInterval) -> TriggerMatch? {
    generation &+= 1
    pending = nil
    // A composed/multi-character event cannot be safely erased one keystroke at a time.
    guard text.count == 1, let character = text.first else {
      reset(atBoundary: false)
      return nil
    }
    if character.isWhitespace || character.isNewline {
      buffer = ""
      atBoundary = true
      return nil
    }
    guard atBoundary else { return nil }
    buffer.append(character)
    let candidates = snippets.filter { $0.keyword.hasPrefix(buffer) }
    guard !candidates.isEmpty, buffer.count <= longestKeyword else {
      buffer = ""
      atBoundary = !character.isLetter && !character.isNumber && character != "_"
      return nil
    }
    guard let exact = candidates.first(where: { $0.keyword == buffer }) else { return nil }
    let deadline =
      candidates.contains(where: { $0.keyword.count > buffer.count }) ? now + delay : nil
    let match = TriggerMatch(snippet: exact, generation: generation, deadline: deadline)
    pending = match
    return match
  }

  mutating func take(_ match: TriggerMatch, now: TimeInterval) -> SnippetRecord? {
    guard match.generation == generation, pending == match,
      match.deadline.map({ now >= $0 }) ?? true
    else { return nil }
    let snippet = match.snippet
    reset(atBoundary: false)
    return snippet
  }
}
