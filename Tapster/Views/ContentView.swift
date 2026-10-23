import SwiftUI

struct ContentView: View {
  @Bindable var state: AppState
  @State private var editorWidth: CGFloat = 420
  @State private var newButtonWidth: CGFloat = 36
  @State private var saveButtonWidth: CGFloat = 64
  @State private var visibility: NavigationSplitViewVisibility = .all
  @SceneStorage("selectedSnippetID") private var restoredID = ""
  @SceneStorage("selectedCollection") private var restoredScope = "all"
  @FocusState private var searchFocused: Bool

  private var unsavedSnippets: [SnippetRecord] {
    guard let draft = state.draft,
      !state.store.snippets.contains(where: { $0.id == draft.id })
    else { return [] }
    return [draft]
  }

  private var snippetTitleItem: some ToolbarContent {
    ToolbarItem(placement: .automatic) {
      if let draft = state.draft {
        Text(draft.name.isEmpty ? "New Snippet" : draft.name)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(
            minWidth: 80,
            idealWidth: max(80, editorWidth - newButtonWidth - saveButtonWidth - 48),
            maxWidth: max(80, editorWidth - newButtonWidth - saveButtonWidth - 48),
            alignment: .leading
          )
          .help(draft.name)
      }
    }
  }

  var body: some View {
    let pendingSnippets = unsavedSnippets
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
        }
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
      .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 400)
      .navigationTitle("Tapster")
    } detail: {
      if let draft = state.draft {
        SnippetEditorView(draft: state.editorBinding(for: draft), state: state)
          .id(draft.id)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.width
          } action: {
            editorWidth = $0
          }
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
    .toolbar {
      if #available(macOS 26.0, *) {
        snippetTitleItem.sharedBackgroundVisibility(.hidden)
      } else {
        snippetTitleItem
      }
      ToolbarItem(placement: .automatic) {
        Button(action: state.newSnippet) {
          Label("New Snippet", systemImage: "square.and.pencil")
        }
        .help("New Snippet (⌘N)")
        .onGeometryChange(for: CGFloat.self) {
          $0.size.width
        } action: {
          newButtonWidth = $0
        }
      }
      ToolbarItem(placement: .automatic) {
        Button(action: { state.save() }) {
          Text("Save").fixedSize().padding(.horizontal, 10)
        }
        .onGeometryChange(for: CGFloat.self) {
          $0.size.width
        } action: {
          saveButtonWidth = $0
        }
        .keyboardShortcut("s")
        .disabled(!state.isDirty || state.draftError != nil)
      }
    }
    .frame(minWidth: 960, minHeight: 600)
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
