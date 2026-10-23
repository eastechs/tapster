import SwiftUI

struct SnippetListView: View {
  @Bindable var state: AppState
  @FocusState private var searchFocused: Bool

  var body: some View {
    let pendingSnippets = state.unsavedSnippets
    VStack(spacing: 0) {
      TextField("Search snippets", text: $state.search)
        .textFieldStyle(SnippetInputStyle())
        .focused($searchFocused)
        .accessibilityLabel("Search snippets")
        .padding(12)
      Divider()
      List(selection: Binding(get: { state.selectedID }, set: { state.select($0) })) {
        ForEach(pendingSnippets + state.filteredSnippets) { snippet in
          let isUnsaved = pendingSnippets.first?.id == snippet.id
          SnippetRow(snippet: snippet, isUnsaved: isUnsaved)
            .tag(snippet.id)
            .contextMenu {
              if !isUnsaved {
                SnippetContextMenu(state: state, snippet: snippet)
              }
            }
        }
      }
      .listStyle(.inset)
      .environment(\.defaultMinListRowHeight, 58)
      .overlay {
        if state.filteredSnippets.isEmpty && state.draft == nil {
          ContentUnavailableView(
            state.search.isEmpty ? "No Snippets" : "No Results",
            systemImage: "text.badge.plus",
            description: Text(
              state.search.isEmpty ? "Create a snippet to get started." : "Try another search."))
        }
      }
    }
    .onChange(of: state.isSearchFocused) { _, _ in searchFocused = true }
  }
}

private struct SnippetRow: View {
  var snippet: SnippetRecord
  var isUnsaved = false
  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(snippet.name).fontWeight(.medium).lineLimit(1)
          if snippet.isFavorite {
            Image(systemName: "star.fill").foregroundStyle(.secondary).font(.caption)
              .accessibilityLabel("Favorite")
          }
        }
        Text(
          isUnsaved ? "Unsaved snippet" : snippet.template.replacingOccurrences(of: "\n", with: " ")
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 4)
      if !snippet.keyword.isEmpty {
        Text(snippet.keyword).font(.system(.caption, design: .monospaced))
          .lineLimit(1).truncationMode(.middle)
          .frame(maxWidth: 96).fixedSize(horizontal: true, vertical: false)
          .help(snippet.keyword)
          .padding(.horizontal, 6).padding(.vertical, 3)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
      }
      if !snippet.isEnabled {
        Image(systemName: "pause.circle").foregroundStyle(.secondary).help("Disabled")
      }
    }
    .padding(.vertical, 7)
  }
}

private struct SnippetContextMenu: View {
  var state: AppState
  var snippet: SnippetRecord
  var body: some View {
    Button("Duplicate") { state.duplicate(snippet) }
    Button(snippet.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
      state.updateSaved(snippet) { $0.isFavorite.toggle() }
    }
    Button(snippet.isEnabled ? "Disable Expansion" : "Enable Expansion") {
      state.updateSaved(snippet) { $0.isEnabled.toggle() }
    }
    Menu("Move to Collection") {
      Button("None") { state.updateSaved(snippet) { $0.collectionID = nil } }
      ForEach(state.store.collections) { collection in
        Button(collection.name) { state.updateSaved(snippet) { $0.collectionID = collection.id } }
      }
    }
    Divider()
    Button("Delete Snippet", role: .destructive) { state.delete(snippet) }
  }
}
