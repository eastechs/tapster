import SwiftUI

struct ContentView: View {
  @Bindable var state: AppState
  @SceneStorage("selectedSnippetID") private var restoredID = ""
  @SceneStorage("selectedCollection") private var restoredScope = "all"

  var body: some View {
    LibrarySplitView(state: state, canSave: state.isDirty && state.draftError == nil)
      .ignoresSafeArea(.container, edges: .top)
      .frame(minWidth: 1100, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
      .background(WindowLifecycleView(state: state))
      .onAppear {
        guard !state.isDirty else { return }
        let selection = LibrarySelection(storedValue: restoredScope)
        if case .collection(let id) = selection,
          !state.store.collections.contains(where: { $0.id == id })
        {
          state.selectScope(.all)
        } else {
          state.selectScope(selection)
        }
        if let id = UUID(uuidString: restoredID),
          state.store.items.contains(where: { $0.id == id })
        {
          state.select(id)
        }
      }
      .onChange(of: state.selectedID) { _, value in restoredID = value?.uuidString ?? "" }
      .onChange(of: state.scope) { _, value in
        restoredScope = value.storedValue
      }
      .alert("Save changes to this item?", isPresented: $state.showingUnsavedAlert) {
        Button("Save") { state.resolveUnsaved(save: true) }.disabled(state.draftError != nil)
        Button("Discard Changes", role: .destructive) { state.resolveUnsaved(save: false) }
        Button("Cancel", role: .cancel) { state.cancelTransition() }
      } message: {
        Text("Your changes have not been saved.")
      }
      .alert(
        "Textend",
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
