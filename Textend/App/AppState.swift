import AppKit
import Observation
import UniformTypeIdentifiers

enum LibrarySelection: Hashable {
  case all, compositions, favorites
  case collection(UUID)

  init(storedValue: String) {
    switch storedValue {
    case "all": self = .all
    case "compositions": self = .compositions
    case "favorites": self = .favorites
    default: self = UUID(uuidString: storedValue).map(Self.collection) ?? .all
    }
  }

  var storedValue: String {
    switch self {
    case .all: "all"
    case .compositions: "compositions"
    case .favorites: "favorites"
    case .collection(let id): id.uuidString
    }
  }

  func contains(_ item: SnippetRecord) -> Bool {
    switch self {
    case .all: !item.isComposition
    case .compositions: item.isComposition
    case .favorites: item.isFavorite
    case .collection(let id): item.collectionID == id
    }
  }
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
  let engine: ExpansionEngine
  let expansionSetup: ExpansionSetup
  var restartApproved = false
  var openQuickAccess: (() -> Void)?
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
    startPaused: Bool = false,
    preferences: UserDefaults = .standard,
    engine: ExpansionEngine? = nil
  ) {
    self.store = store
    self.preferences = preferences
    let engine = engine ?? ExpansionEngine(preferences: preferences)
    self.engine = engine
    expansionSetup = ExpansionSetup(engine: engine, preferences: preferences)
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
    engine.updateLibrary(store.library)
    store.onChange = { [weak self] in self?.libraryDidChange() }
    if startEngine { engine.start(initiallyPaused: startPaused) }
  }

  var isDirty: Bool { draft != baseline }
  var isNewDraft: Bool { draft != nil && baseline == nil }
  var filteredSnippets: [SnippetRecord] {
    let matches = Set(store.library.search(search, bundleID: nil, allApps: true).map(\.id))
    return store.items.filter { scope.contains($0) && matches.contains($0.id) }
      .sorted(by: sortOrder.precedes)
  }

  var unsavedSnippets: [SnippetRecord] {
    guard let draft, scope.contains(draft), !store.items.contains(where: { $0.id == draft.id })
    else { return [] }
    return [draft]
  }

  var remoteDraftDeleted: Bool {
    baseline != nil && !store.items.contains { $0.id == baseline?.id }
  }

  var remoteDraftChanged: Bool {
    guard isDirty, let baseline,
      let saved = store.items.first(where: { $0.id == baseline.id })
    else { return false }
    return saved != baseline
  }

  var copyError: String? {
    guard let draft else { return nil }
    do {
      try store.libraryForDraft(draft).validateContent(draft)
      return nil
    } catch { return error.localizedDescription }
  }

  private func libraryDidChange() {
    engine.updateLibrary(store.library)
    if case .collection(let id) = scope, !store.collections.contains(where: { $0.id == id }) {
      scope = draft?.isComposition == true ? .compositions : .all
      search = ""
    }
    if !isDirty, let selectedID {
      if let saved = store.items.first(where: { $0.id == selectedID }) {
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
      if let baseline, let remote = store.items.first(where: { $0.id == draft.id }) {
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
      if let snippet = self.store.items.first(where: { $0.id == id }) {
        self.reveal(snippet)
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

  func newComposition() { newSnippet(composition: true) }

  func newSnippet() { newSnippet(composition: false) }

  private func newSnippet(composition: Bool) {
    transition { [weak self] in
      guard let self else { return }
      var snippet = SnippetRecord(
        name: composition ? "Untitled Composition" : "Untitled Snippet",
        blocks: composition ? [] : nil)
      if case .collection(let id) = self.scope { snippet.collectionID = id }
      self.scope = composition ? .compositions : .all
      self.search = ""
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
      if let baseline, let remote = store.items.first(where: { $0.id == draft.id }) {
        record = draft.mergingChanges(from: baseline, into: remote)
      } else {
        record = draft
      }
      try store.save(record)
      if let saved = store.items.first(where: { $0.id == draft.id }) { load(saved) }
      engine.updateLibrary(store.library)
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
      copy.blocks = copy.blocks?.map { block in
        var value = block
        value.id = UUID()
        return value
      }
      copy.placeholders = copy.placeholders.map {
        var p = $0
        p.id = UUID()
        return p
      }
      self?.reveal(copy)
      self?.draft = copy
      self?.baseline = nil
      self?.selectedID = copy.id
    }
  }

  func delete(_ snippet: SnippetRecord) {
    transition { [weak self] in
      self?.perform {
        guard let self else { return }
        let dependents = self.store.compositions.filter {
          $0.blocks.contains { $0.snippetID == snippet.id }
        }
        if !dependents.isEmpty {
          let alert = NSAlert()
          alert.messageText = "Delete a source snippet?"
          alert.informativeText =
            "Used by " + dependents.map { $0.metadata.name }.joined(separator: ", ")
            + ". Those Compositions will stop expanding until repaired."
          alert.addButton(withTitle: "Cancel")
          alert.addButton(withTitle: "Delete")
          guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
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
        guard var record = self.store.items.first(where: { $0.id == snippet.id }) else { return }
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

  func saveCollection(name: String, appBundleIDs: [String]? = nil) throws {
    var record =
      collectionToEdit ?? CollectionRecord(name: name, sortOrder: store.collections.count)
    if let baseline = collectionToEdit {
      guard let remote = store.collections.first(where: { $0.id == baseline.id }) else {
        throw TemplateError.invalid(
          "This collection was deleted elsewhere. Cancel and create a new collection.")
      }
      record = remote
      if name != baseline.name { record.name = name }
      if appBundleIDs != baseline.appBundleIDs { record.appBundleIDs = appBundleIDs }
    } else {
      record.name = name
      record.appBundleIDs = appBundleIDs
    }
    try store.saveCollection(record)
  }

  func deleteCollection(_ id: UUID) {
    transition { [weak self] in
      self?.perform {
        guard let self else { return }
        if let collection = self.store.collections.first(where: { $0.id == id }),
          collection.appBundleIDs != nil
        {
          let alert = NSAlert()
          alert.messageText = "Delete restricted collection?"
          alert.informativeText =
            "Its retained items become available in all apps. New keyword conflicts will pause automatic expansion."
          alert.addButton(withTitle: "Cancel")
          alert.addButton(withTitle: "Delete")
          guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        try self.store.deleteCollection(id)
        if self.scope == .collection(id) {
          self.scope = self.draft?.isComposition == true ? .compositions : .all
        }
        if let selected = self.store.items.first(where: { $0.id == self.selectedID }) {
          self.load(selected)
        }
      }
    }
  }

  func importBackup(onError: ((Error) -> Void)? = nil) {
    transition { [weak self] in self?.showImportPanel(onError: onError) }
  }

  func exportBackup(onError: ((Error) -> Void)? = nil) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Textend-backup.json"
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.perform(onError: onError) {
        guard let self else { return }
        try self.store.exportArchive().write(to: url, options: .atomic)
      }
    }
  }

  func requestQuit() {
    NSApplication.shared.terminate(nil)
  }

  func discardDraft() {
    if let id = baseline?.id, let saved = store.items.first(where: { $0.id == id }) {
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
    if store.items.contains(where: { !$0.keyword.isEmpty && $0.keyword == copy.keyword }) {
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
      let value = try store.libraryForDraft(draft).resolve(
        draft, clipboard: TextInsertionService.clipboardText(from: .general)
      ).text
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(value, forType: .string)
    } catch { errorMessage = error.localizedDescription }
  }

  func perform(onError: ((Error) -> Void)? = nil, _ action: () throws -> Void) {
    do {
      try action()
      engine.updateLibrary(store.library)
    } catch {
      if let onError { onError(error) } else { errorMessage = error.localizedDescription }
    }
  }

  private func showImportPanel(onError: ((Error) -> Void)?) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.perform(onError: onError) {
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

  private func reveal(_ item: SnippetRecord) {
    if !scope.contains(item) { scope = item.isComposition ? .compositions : .all }
    if !filteredSnippets.contains(where: { $0.id == item.id }) { search = "" }
  }

  private func load(_ snippet: SnippetRecord) {
    selectedID = snippet.id
    draft = snippet
    baseline = snippet
  }
}
