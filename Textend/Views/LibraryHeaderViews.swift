import SwiftUI

extension AppState {
  var scopeItemName: String {
    switch scope {
    case .all: "Snippet"
    case .compositions: "Composition"
    case .favorites, .collection: "Item"
    }
  }

  var scopeSearchPrompt: String { "Search \(scopeItemName.lowercased())s" }

  var scopeEmptyDescription: String {
    switch scope {
    case .all: "Create a snippet to get started."
    case .compositions: "Create a Composition to get started."
    case .favorites: "Mark a snippet or Composition as a favorite."
    case .collection: "Add a snippet or Composition to this collection."
    }
  }

  var scopeTitle: String {
    switch scope {
    case .all: "All Snippets"
    case .compositions: "Compositions"
    case .favorites: "Favorites"
    case .collection(let id): store.collections.first(where: { $0.id == id })?.name ?? "Collection"
    }
  }
}

struct LibraryHeaderView: View {
  var state: AppState

  var body: some View {
    let count = state.unsavedSnippets.count + state.filteredSnippets.count
    VStack(alignment: .leading, spacing: 2) {
      Text(state.scopeTitle).font(.headline).lineLimit(1).help(state.scopeTitle)
      Text("\(count) \(state.scopeItemName)\(count == 1 ? "" : "s")")
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct SnippetSortMenu: View {
  @Bindable var state: AppState

  var body: some View {
    Menu {
      Picker("Sort by", selection: $state.sortOrder) {
        ForEach(SnippetSortOrder.allCases) { order in
          Text(order.title).tag(order)
        }
      }
    } label: {
      Image(systemName: "arrow.up.arrow.down").controlHitArea(minHeight: 36)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .help("Sort \(state.scopeItemName.lowercased())s: \(state.sortOrder.title)")
    .accessibilityLabel("Sort \(state.scopeItemName.lowercased())s")
    .accessibilityValue(state.sortOrder.title)
  }
}

struct SnippetHeaderView: View {
  var state: AppState

  var body: some View {
    HStack(spacing: 8) {
      if let draft = state.draft {
        Toggle(isOn: state.editorBinding(for: draft).isFavorite) {
          Image(systemName: draft.isFavorite ? "star.fill" : "star").controlHitArea()
        }
        .toggleStyle(.button).buttonStyle(.borderless).fixedSize()
        .help("Favorite snippet").accessibilityLabel("Favorite snippet")
        Text(draft.name.isEmpty ? "New Snippet" : draft.name)
          .font(.headline).lineLimit(1).truncationMode(.tail).help(draft.name)
      }
      Spacer(minLength: 0)
    }
  }
}
