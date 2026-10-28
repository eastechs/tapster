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
          libraryRow(
            "All Snippets", symbol: "doc.text", selection: .all, count: state.store.snippets.count)
          libraryRow(
            "Compositions", symbol: "square.stack", selection: .compositions,
            count: state.store.items.filter(\.isComposition).count)
          libraryRow("Favorites", symbol: "star", selection: .favorites)
        }
        Section("Collections") {
          ForEach(state.store.collections) { collection in
            Label(collection.name, systemImage: "folder")
              .help(
                collection.appBundleIDs?.map(ApplicationLabel.name).joined(separator: ", ")
                  ?? "All apps"
              )
              .tag(LibrarySelection.collection(collection.id))
              .textendSelection(state.scope == .collection(collection.id))
              .contextMenu {
                Button("Edit Collection…") { state.editCollection(collection) }
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
          .padding(.horizontal, 12).padding(.vertical, 8).controlHitArea()
      }
      .buttonStyle(.borderless)
      .help("New Collection (⇧⌘N)")
      Divider()
      HStack(spacing: 4) {
        Button {
          state.engine.setEnabled(!state.engine.isEnabled, requestPermission: true)
        } label: {
          HStack(spacing: 6) {
            Circle().fill(state.engine.status == .active ? Color.green : Color.secondary).frame(
              width: 7, height: 7)
            Text(state.engine.status.rawValue).font(.caption).lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading).controlHitArea()
        }
        .buttonStyle(.plain)
        .help(state.engine.isEnabled ? "Pause expansion" : "Enable expansion")
        SettingsLink { Image(systemName: "gearshape").controlHitArea() }
          .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
      }
      .padding(12)
    }
  }

  private func libraryRow(
    _ title: String, symbol: String, selection: LibrarySelection, count: Int? = nil
  ) -> some View {
    Label {
      HStack {
        Text(title)
        if let count {
          Spacer()
          Text("\(count)").foregroundStyle(.secondary)
        }
      }
    } icon: {
      Image(systemName: symbol)
    }
    .tag(selection)
    .textendSelection(state.scope == selection)
  }
}

struct CollectionSheet: View {
  var state: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var restricted = false
  @State private var bundleIDs: [String] = []
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(state.collectionToEdit == nil ? "New Collection" : "Edit Collection").font(.headline)
      TextField("Collection name", text: $name).onSubmit(save)
      Picker("Available in", selection: $restricted) {
        Text("All Apps").tag(false)
        Text("Selected Apps").tag(true)
      }.pickerStyle(.segmented)
      if restricted {
        ScrollView {
          VStack(spacing: 10) {
            ForEach(bundleIDs, id: \.self) { id in
              HStack {
                ApplicationLabel(bundleID: id)
                Spacer()
                Button {
                  bundleIDs.removeAll { $0 == id }
                } label: {
                  Image(systemName: "minus.circle").controlHitArea()
                }
                .buttonStyle(.borderless).accessibilityLabel("Remove \(ApplicationLabel.name(id))")
              }
            }
          }
        }.frame(maxHeight: 180)
        Button("Add Applications…") {
          ApplicationLabel.choose { ids in bundleIDs = Array(Set(bundleIDs + ids)).sorted() }
        }
        Text(
          "Update Textend on every synced Mac before using app restrictions. Older versions cannot enforce them."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      if let error { Text(error).foregroundStyle(.red).font(.callout) }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save", action: save).keyboardShortcut(.defaultAction)
          .disabled(
            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || (restricted && bundleIDs.isEmpty))
      }
    }
    .textFieldStyle(SnippetInputStyle())
    .padding(24).frame(width: 440)
    .onAppear {
      name = state.collectionToEdit?.name ?? ""
      restricted = state.collectionToEdit?.appBundleIDs != nil
      bundleIDs = state.collectionToEdit?.appBundleIDs ?? []
    }
  }

  private func save() {
    do {
      try state.saveCollection(
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        appBundleIDs: restricted ? bundleIDs : nil)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
