import SwiftUI
import UniformTypeIdentifiers

struct CompositionBlocksView: View {
  @Binding var draft: SnippetRecord
  var state: AppState
  @State private var choosingSnippet = false
  @State private var query = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Composition").font(.headline)
      Text("Source edits update this Composition. Literal text is inserted exactly as written.")
        .font(.caption).foregroundStyle(.secondary)
      ForEach(Array((draft.blocks ?? []).enumerated()), id: \.element.id) { index, block in
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
              .draggable(block.id.uuidString)
              .accessibilityLabel("Drag block \(index + 1)")
            Text("Block \(index + 1)").font(.subheadline)
            Spacer()
            Button {
              move(block.id, by: -1)
            } label: {
              Image(systemName: "arrow.up").controlHitArea()
            }
            .disabled(index == 0).accessibilityLabel("Move block up")
            Button {
              move(block.id, by: 1)
            } label: {
              Image(systemName: "arrow.down").controlHitArea()
            }
            .disabled(index == (draft.blocks?.count ?? 0) - 1).accessibilityLabel("Move block down")
            Button {
              draft.blocks?.removeAll { $0.id == block.id }
            } label: {
              Image(systemName: "trash").controlHitArea()
            }
            .accessibilityLabel("Remove block")
          }.buttonStyle(.borderless)
          if let id = block.snippetID {
            if let source = state.store.snippets.first(where: { $0.id == id }) {
              HStack {
                Label(source.name, systemImage: "doc.text").fontWeight(.medium)
                Spacer()
                Button("Open") { state.select(id) }
              }
              Text(source.template).font(.system(.body, design: .monospaced)).lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
              Label(
                "Source snippet unavailable. Remove this block or wait for sync.",
                systemImage: "exclamationmark.triangle"
              )
              .foregroundStyle(.orange)
            }
          } else {
            TextField("Literal text", text: binding(block.id).text, axis: .vertical)
              .lineLimit(2...8).textFieldStyle(SnippetInputStyle())
          }
          if index < (draft.blocks?.count ?? 0) - 1 {
            Picker("Follow with", selection: binding(block.id).separator) {
              ForEach(CompositionSeparator.allCases) { Text($0.title).tag($0) }
            }.fixedSize()
          }
        }
        .padding(12).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: String.self) { values, _ in
          guard let text = values.first, let dragged = UUID(uuidString: text), dragged != block.id,
            let from = draft.blocks?.firstIndex(where: { $0.id == dragged }),
            let to = draft.blocks?.firstIndex(where: { $0.id == block.id }),
            let value = draft.blocks?.remove(at: from)
          else { return false }
          draft.blocks?.insert(value, at: to)
          return true
        }
      }
      HStack {
        Button("Add Snippet") { choosingSnippet = true }
        Button("Add Literal Text") { draft.blocks?.append(CompositionBlock()) }
      }
    }
    .sheet(isPresented: $choosingSnippet) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Add Snippet").font(.headline)
        TextField("Search snippets", text: $query).textFieldStyle(SnippetInputStyle())
        List(
          state.store.snippets.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
              || $0.template.localizedCaseInsensitiveContains(query)
          }
        ) { snippet in
          Button {
            draft.blocks?.append(CompositionBlock(snippetID: snippet.id))
            choosingSnippet = false
            query = ""
          } label: {
            VStack(alignment: .leading) {
              Text(snippet.name).fontWeight(.medium)
              Text(snippet.template).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
              .controlHitArea()
          }.buttonStyle(.plain)
        }.frame(height: 260)
        HStack {
          Spacer()
          Button("Cancel") { choosingSnippet = false }.keyboardShortcut(.cancelAction)
        }
      }.padding(24).frame(width: 440)
    }
  }

  private func binding(_ id: UUID) -> Binding<CompositionBlock> {
    Binding(
      get: { draft.blocks?.first { $0.id == id } ?? CompositionBlock(id: id) },
      set: { value in
        guard let index = draft.blocks?.firstIndex(where: { $0.id == id }) else { return }
        draft.blocks?[index] = value
      })
  }
  private func move(_ id: UUID, by offset: Int) {
    guard let index = draft.blocks?.firstIndex(where: { $0.id == id }),
      let count = draft.blocks?.count, (0..<count).contains(index + offset)
    else { return }
    draft.blocks?.swapAt(index, index + offset)
  }
}
