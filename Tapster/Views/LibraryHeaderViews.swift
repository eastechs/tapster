import SwiftUI

extension AppState {
  var unsavedSnippets: [SnippetRecord] {
    guard let draft, !store.snippets.contains(where: { $0.id == draft.id }) else { return [] }
    return [draft]
  }

  var scopeTitle: String {
    switch scope {
    case .all: "All Snippets"
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
      Text("\(count) \(count == 1 ? "Snippet" : "Snippets")")
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
      Image(systemName: "arrow.up.arrow.down")
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .help("Sort snippets: \(state.sortOrder.title)")
    .accessibilityLabel("Sort snippets")
    .accessibilityValue(state.sortOrder.title)
  }
}

struct SnippetHeaderView: View {
  var state: AppState

  var body: some View {
    HStack(spacing: 8) {
      if let draft = state.draft {
        Toggle(isOn: state.editorBinding(for: draft).isFavorite) {
          Image(systemName: draft.isFavorite ? "star.fill" : "star")
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
