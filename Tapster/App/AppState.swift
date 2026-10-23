import AppKit
import Observation
import UniformTypeIdentifiers

enum LibrarySelection: Hashable {
  case all, favorites
  case collection(UUID)
}

@MainActor @Observable final class AppState {
  let store: LibraryStore
  let engine = ExpansionEngine()
  var scope: LibrarySelection = .all
  var selectedID: UUID?
  var draft: SnippetRecord?
  private var baseline: SnippetRecord?
  var search = ""
  var sampleClipboard = "Fix login redirect"
  var errorMessage: String?
  var isSearchFocused = false
  var pendingAction: (() -> Void)?
  var showingUnsavedAlert = false
  var collectionToEdit: CollectionRecord?
  var showingCollectionSheet = false

  init(store: LibraryStore, seedExamples: Bool = true, startEngine: Bool = true) {
    self.store = store
    if seedExamples && !UserDefaults.standard.bool(forKey: "hasCreatedLibrary") {
      do {
        try store.seedExamples()
        UserDefaults.standard.set(true, forKey: "hasCreatedLibrary")
      } catch { errorMessage = error.localizedDescription }
    }
    if let first = store.snippets.first(where: { $0.name == "Git Commit" }) ?? store.snippets.first
    {
      load(first)
    }
    engine.updateSnippets(store.snippets)
    if startEngine { engine.start() }
  }

  var isDirty: Bool { draft != baseline }
  var filteredSnippets: [SnippetRecord] {
    store.snippets.filter { snippet in
      let inScope: Bool
      switch scope {
      case .all: inScope = true
      case .favorites: inScope = snippet.isFavorite
      case .collection(let id): inScope = snippet.collectionID == id
      }
      let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
      return inScope
        && (query.isEmpty
          || [snippet.name, snippet.keyword, snippet.template].contains {
            $0.localizedCaseInsensitiveContains(query)
          })
    }
  }

  var draftError: String? {
    guard let draft else { return nil }
    do {
      try LibraryValidation.validate(draft, among: store.snippets)
      return nil
    } catch { return error.localizedDescription }
  }

  func select(_ id: UUID?) {
    guard id != selectedID else { return }
    transition { [weak self] in
      guard let self else { return }
      if let snippet = self.store.snippets.first(where: { $0.id == id }) {
        self.load(snippet)
      } else {
        self.draft = nil
        self.baseline = nil
        self.selectedID = nil
      }
    }
  }

  func selectScope(_ value: LibrarySelection) {
    guard value != scope else { return }
    transition { [weak self] in
      guard let self else { return }
      self.scope = value
      self.selectedID = nil
      self.draft = nil
      self.baseline = nil
      if let first = self.filteredSnippets.first { self.load(first) }
    }
  }

  func newSnippet() {
    transition { [weak self] in
      guard let self else { return }
      var snippet = SnippetRecord(name: "Untitled Snippet")
      if case .collection(let id) = self.scope { snippet.collectionID = id }
      self.draft = snippet
      self.baseline = nil
      self.selectedID = snippet.id
    }
  }

  @discardableResult func save() -> Bool {
    guard let draft else { return true }
    do {
      try store.save(draft)
      if let saved = store.snippets.first(where: { $0.id == draft.id }) { load(saved) }
      engine.updateSnippets(store.snippets)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func resolveUnsaved(save: Bool) {
    let action = pendingAction
    if save && !self.save() {
      pendingAction = nil
      return
    }
    if !save { discardDraft() }
    pendingAction = nil
    action?()
  }

  func cancelTransition() { pendingAction = nil }

  func duplicate(_ snippet: SnippetRecord) {
    transition { [weak self] in
      var copy = snippet
      copy.id = UUID()
      copy.name += " Copy"
      copy.keyword = ""
      copy.createdAt = Date()
      copy.updatedAt = Date()
      copy.placeholders = copy.placeholders.map {
        var p = $0
        p.id = UUID()
        return p
      }
      self?.draft = copy
      self?.baseline = nil
      self?.selectedID = copy.id
    }
  }

  func delete(_ snippet: SnippetRecord) {
    transition { [weak self] in
      self?.perform {
        guard let self else { return }
        try self.store.deleteSnippet(snippet.id)
        if self.selectedID == snippet.id {
          self.draft = nil
          self.baseline = nil
          self.selectedID = nil
        }
      }
    }
  }

  func updateSaved(_ snippet: SnippetRecord, mutate: @escaping (inout SnippetRecord) -> Void) {
    transition { [weak self] in
      self?.perform {
        guard let self else { return }
        guard var record = self.store.snippets.first(where: { $0.id == snippet.id }) else { return }
        mutate(&record)
        try self.store.save(record)
        if self.selectedID == record.id { self.load(record) }
      }
    }
  }

  func editCollection(_ collection: CollectionRecord?) {
    collectionToEdit = collection
    showingCollectionSheet = true
  }

  func saveCollection(name: String) {
    perform {
      var record =
        collectionToEdit ?? CollectionRecord(name: name, sortOrder: store.collections.count)
      record.name = name
      try store.saveCollection(record)
    }
  }

  func deleteCollection(_ id: UUID) {
    transition { [weak self] in
      self?.perform {
        guard let self else { return }
        try self.store.deleteCollection(id)
        self.scope = .all
        if let selected = self.store.snippets.first(where: { $0.id == self.selectedID }) {
          self.load(selected)
        }
      }
    }
  }

  func importBackup() {
    transition { [weak self] in self?.showImportPanel() }
  }

  func exportBackup() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Tapster-backup.json"
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.perform {
        guard let self else { return }
        try self.store.exportArchive().write(to: url, options: .atomic)
      }
    }
  }

  func requestQuit() {
    NSApplication.shared.terminate(nil)
  }

  func discardDraft() {
    draft = baseline
    selectedID = baseline?.id
  }

  func copyExpandedText() {
    guard let draft else { return }
    do {
      let value = try TemplateResolver.resolve(
        draft, clipboard: NSPasteboard.general.string(forType: .string))
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
    } catch { errorMessage = error.localizedDescription }
  }

  func perform(_ action: () throws -> Void) {
    do {
      try action()
      engine.updateSnippets(store.snippets)
    } catch { errorMessage = error.localizedDescription }
  }

  private func showImportPanel() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.perform {
        guard let self else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try self.store.importArchive(Data(contentsOf: url))
      }
    }
  }

  private func transition(_ action: @escaping () -> Void) {
    if isDirty {
      pendingAction = action
      showingUnsavedAlert = true
    } else {
      action()
    }
  }

  private func load(_ snippet: SnippetRecord) {
    selectedID = snippet.id
    draft = snippet
    baseline = snippet
  }
}
