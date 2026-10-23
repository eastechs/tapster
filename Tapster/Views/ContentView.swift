import SwiftUI

struct ContentView: View {
  @Bindable var state: AppState
  @State private var visibility: NavigationSplitViewVisibility = .all
  @SceneStorage("selectedSnippetID") private var restoredID = ""
  @SceneStorage("selectedCollection") private var restoredScope = "all"
  @FocusState private var searchFocused: Bool

  var body: some View {
    NavigationSplitView(columnVisibility: $visibility) {
      SidebarView(state: state)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 260)
    } content: {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          TextField("Search snippets", text: $state.search)
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .accessibilityLabel("Search snippets")
          Button(action: state.newSnippet) { Image(systemName: "plus") }
            .help("New Snippet (⌘N)")
            .accessibilityLabel("New snippet")
        }
        .padding(12)
        Divider()
        List(selection: Binding(get: { state.selectedID }, set: { state.select($0) })) {
          if let draft = state.draft, !state.store.snippets.contains(where: { $0.id == draft.id }) {
            SnippetRow(snippet: draft, isUnsaved: true).tag(draft.id)
          }
          ForEach(state.filteredSnippets) { snippet in
            SnippetRow(snippet: snippet)
              .tag(snippet.id)
              .contextMenu { SnippetContextMenu(state: state, snippet: snippet) }
          }
        }
        .listStyle(.inset)
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
      .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
    } detail: {
      if let draft = state.draft {
        SnippetEditorView(draft: state.editorBinding(for: draft), state: state)
          .id(draft.id)
      } else {
        ContentUnavailableView {
          Label("Your words, a shortcut away", systemImage: "text.insert")
        } description: {
          Text("Select a snippet or create a new one.")
        } actions: {
          Button("New Snippet", action: state.newSnippet)
        }
      }
    }
    .navigationTitle("Tapster")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Save", action: { state.save() })
          .keyboardShortcut("s")
          .disabled(!state.isDirty || state.draftError != nil)
      }
    }
    .frame(minWidth: 870, minHeight: 600)
    .background(WindowLifecycleView(state: state))
    .onAppear {
      guard !state.isDirty else { return }
      let selection: LibrarySelection
      if restoredScope == "favorites" {
        selection = .favorites
      } else if let id = UUID(uuidString: restoredScope),
        state.store.collections.contains(where: { $0.id == id })
      {
        selection = .collection(id)
      } else {
        selection = .all
      }
      state.selectScope(selection)
      if let id = UUID(uuidString: restoredID),
        state.store.snippets.contains(where: { $0.id == id })
      {
        state.select(id)
      }
    }
    .onChange(of: state.selectedID) { _, value in restoredID = value?.uuidString ?? "" }
    .onChange(of: state.scope) { _, value in
      switch value {
      case .all: restoredScope = "all"
      case .favorites: restoredScope = "favorites"
      case .collection(let id): restoredScope = id.uuidString
      }
    }
    .onChange(of: state.isSearchFocused) { _, _ in searchFocused = true }
    .alert("Save changes to this snippet?", isPresented: $state.showingUnsavedAlert) {
      Button("Save") { state.resolveUnsaved(save: true) }.disabled(state.draftError != nil)
      Button("Discard Changes", role: .destructive) { state.resolveUnsaved(save: false) }
      Button("Cancel", role: .cancel) { state.cancelTransition() }
    } message: {
      Text("Your changes have not been saved.")
    }
    .alert(
      "Tapster",
      isPresented: Binding(
        get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) { state.errorMessage = nil }
    } message: {
      Text(state.errorMessage ?? "")
    }
    .sheet(isPresented: $state.showingCollectionSheet) {
      CollectionSheet(state: state)
    }
  }
}

private struct SnippetRow: View {
  var snippet: SnippetRecord
  var isUnsaved = false
  var body: some View {
    HStack(spacing: 10) {
      if snippet.isFavorite {
        Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(snippet.name).fontWeight(.medium).lineLimit(1)
        Text(
          isUnsaved ? "Unsaved snippet" : snippet.template.replacingOccurrences(of: "\n", with: " ")
        )
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 4)
      if !snippet.keyword.isEmpty {
        Text(snippet.keyword).font(.system(.caption, design: .monospaced))
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
