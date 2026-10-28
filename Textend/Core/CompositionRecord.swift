import Foundation

enum CompositionSeparator: String, Codable, CaseIterable, Identifiable {
  case none, space, line, paragraph
  var id: String { rawValue }
  var title: String {
    switch self {
    case .none: "None"
    case .space: "Space"
    case .line: "New Line"
    case .paragraph: "Blank Line"
    }
  }
  var text: String {
    switch self {
    case .none: ""
    case .space: " "
    case .line: "\n"
    case .paragraph: "\n\n"
    }
  }
}

struct CompositionBlock: Codable, Equatable, Identifiable {
  var id = UUID()
  var snippetID: UUID?
  var text = ""
  var separator: CompositionSeparator = .line
}

struct CompositionRecord: Codable, Equatable, Identifiable {
  var metadata: SnippetRecord
  var blocks: [CompositionBlock]
  var id: UUID { metadata.id }
  init(_ item: SnippetRecord) {
    metadata = item
    metadata.blocks = nil
    blocks = item.blocks ?? []
  }
  var item: SnippetRecord {
    var value = metadata
    value.blocks = blocks
    return value
  }
}
