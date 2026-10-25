import AppKit
import Observation
import UniformTypeIdentifiers

enum LibrarySelection: Hashable {
  case all, favorites
  case collection(UUID)
}

enum SnippetSortOrder: String, CaseIterable, Identifiable {
  case name, createdAt
  var id: String { rawValue }
  var title: String { self == .name ? "A–Z" : "Created At (Newest First)" }

  func precedes(_ lhs: SnippetRecord, _ rhs: SnippetRecord) -> Bool {
    if self == .createdAt, lhs.createdAt != rhs.createdAt {
      return lhs.createdAt > rhs.createdAt
    }
    let comparison = lhs.name.localizedStandardCompare(rhs.name)
    return comparison == .orderedSame
      ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
  }
}

@MainActor @Observable final class AppState {
  let store: LibraryStore
  private let preferences: UserDefaults
  var sortOrder: SnippetSortOrder {
    didSet { preferences.set(sortOrder.rawValue, forKey: "snippetSortOrder") }
  }
  let engine = ExpansionEngine()
  var restartApproved = false
  var scope: LibrarySelection = .all
  var selectedID: UUID?
  var draft: SnippetRecord?
  private var baseline: SnippetRecord?
  var search = ""
  var sampleClipboard = ""
  var errorMessage: String?
  var isSearchFocused = false
  var pendingAction: (() -> Void)?
  var showingUnsavedAlert = false
  var collectionToEdit: CollectionRecord?
  var showingCollectionSheet = false

  init(
    store: LibraryStore, seedExamples: Bool = false, startEngine: Bool = true,
    preferences: UserDefaults = .standard
  ) {
    self.store = store
    self.preferences = preferences
    sortOrder =
      SnippetSortOrder(rawValue: preferences.string(forKey: "snippetSortOrder") ?? "") ?? .name
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
    engine.updateSnippets(store.expansionSnippets)
    store.onChange = { [weak self] in self?.libraryDidChange() }
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
    }.sorted(by: sortOrder.precedes)
  }

  var remoteDraftDeleted: Bool {
    baseline != nil && !store.snippets.contains { $0.id == baseline?.id }
  }

  var remoteDraftChanged: Bool {
    guard isDirty, let baseline,
      let saved = store.snippets.first(where: { $0.id == baseline.id })
    else { return false }
    return saved != baseline
  }

  var copyError: String? {
    guard let draft else { return nil }
    do {
      try LibraryValidation.validate(draft, among: [draft])
      return nil
    } catch { return error.localizedDescription }
  }

  private func libraryDidChange() {
    engine.updateSnippets(store.expansionSnippets)
    if case .collection(let id) = scope, !store.collections.contains(where: { $0.id == id }) {
      scope = .all
    }
    if !isDirty, let selectedID {
      if let saved = store.snippets.first(where: { $0.id == selectedID }) {
        load(saved)
      } else {
        draft = nil
        baseline = nil
        self.selectedID = nil
      }
    }
  }

  var draftError: String? {
    guard let draft else { return nil }
    do {
      let proposed: SnippetRecord
      if let baseline, let remote = store.snippets.first(where: { $0.id == draft.id }) {
        proposed = draft.mergingChanges(from: baseline, into: remote)
      } else {
        proposed = draft
      }
      try store.validateSave(proposed)
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
      guard !remoteDraftDeleted else {
        throw TemplateError.invalid(
          "This snippet was deleted on another Mac. Save it as a new snippet or discard your draft."
        )
      }
      let record: SnippetRecord
      if let baseline, let remote = store.snippets.first(where: { $0.id == draft.id }) {
        record = draft.mergingChanges(from: baseline, into: remote)
      } else {
        record = draft
      }
      try store.save(record)
      if let saved = store.snippets.first(where: { $0.id == draft.id }) { load(saved) }
      engine.updateSnippets(store.expansionSnippets)
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
    panel.nameFieldStringValue = "Textend-backup.json"
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
    if let id = baseline?.id, let saved = store.snippets.first(where: { $0.id == id }) {
      load(saved)
    } else {
      draft = nil
      baseline = nil
      selectedID = nil
    }
  }

  func saveDeletedDraftAsNew() {
    guard remoteDraftDeleted, var copy = draft else { return }
    copy.id = UUID()
    copy.createdAt = Date()
    if store.snippets.contains(where: { !$0.keyword.isEmpty && $0.keyword == copy.keyword }) {
      copy.keyword = ""
    }
    if !store.collections.contains(where: { $0.id == copy.collectionID }) {
      copy.collectionID = nil
    }
    draft = copy
    selectedID = copy.id
    baseline = nil
    _ = save()
  }

  func addExamples() {
    transition { [weak self] in self?.perform { try self?.store.seedExamples() } }
  }

  func copyExpandedText() {
    guard let draft else { return }
    do {
      let value = try TemplateResolver.resolve(
        draft, clipboard: TextInsertionService.clipboardText(from: .general))
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
    } catch { errorMessage = error.localizedDescription }
  }

  func perform(_ action: () throws -> Void) {
    do {
      try action()
      engine.updateSnippets(store.expansionSnippets)
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
