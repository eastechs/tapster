import SwiftUI

struct SidebarView: View {
  @Bindable var state: AppState

  var body: some View {
    VStack(spacing: 0) {
      List(
        selection: Binding<LibrarySelection?>(
          get: { state.scope }, set: { if let scope = $0 { state.selectScope(scope) } })
      ) {
        Section {
          Label {
            HStack {
              Text("All Snippets")
              Spacer()
              Text("\(state.store.snippets.count)").foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "doc.text")
          }
          .tag(LibrarySelection.all)
          Label("Favorites", systemImage: "star").tag(LibrarySelection.favorites)
        }
        Section("Collections") {
          ForEach(state.store.collections) { collection in
            Label(collection.name, systemImage: "folder")
              .tag(LibrarySelection.collection(collection.id))
              .contextMenu {
                Button("Rename Collection…") { state.editCollection(collection) }
                Button("Delete Collection", role: .destructive) {
                  state.deleteCollection(collection.id)
                }
              }
          }
        }
      }
      .listStyle(.sidebar)
      Button {
        state.editCollection(nil)
      } label: {
        Label("New Collection", systemImage: "folder.badge.plus")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .help("New Collection (⇧⌘N)")
      Divider()
      HStack {
        Button {
          state.engine.setEnabled(!state.engine.isEnabled, requestPermission: true)
        } label: {
          HStack(spacing: 6) {
            Circle().fill(state.engine.status == .active ? Color.green : Color.secondary).frame(
              width: 7, height: 7)
            Text(state.engine.status.rawValue).font(.caption).lineLimit(1)
          }
        }
        .buttonStyle(.plain)
        .help(state.engine.isEnabled ? "Pause expansion" : "Enable expansion")
        Spacer(minLength: 4)
        SettingsLink { Image(systemName: "gearshape") }
          .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
      }
      .padding(12)
    }
  }
}

struct CollectionSheet: View {
  var state: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(state.collectionToEdit == nil ? "New Collection" : "Rename Collection").font(.headline)
      TextField("Collection name", text: $name)
        .onSubmit(save)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save", action: save).keyboardShortcut(.defaultAction)
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .textFieldStyle(SnippetInputStyle())
    .padding(24).frame(width: 390)
    .onAppear { name = state.collectionToEdit?.name ?? "" }
  }

  private func save() {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    state.saveCollection(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
    dismiss()
  }
}
