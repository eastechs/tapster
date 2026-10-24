import SwiftUI

private struct HelpSearchActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var helpSearchAction: (() -> Void)? {
    get { self[HelpSearchActionKey.self] }
    set { self[HelpSearchActionKey.self] = newValue }
  }
}

struct HelpView: View {
  @Environment(\.textendAccent) private var accent
  @State private var selection: String? = "start"
  @State private var search = ""
  @FocusState private var searchFocused: Bool

  private var topics: [HelpTopic] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return HelpTopic.all.filter { query.isEmpty || $0.searchText.localizedStandardContains(query) }
  }

  var body: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        TextField("Search Help", text: $search)
          .textFieldStyle(.roundedBorder).focused($searchFocused)
          .accessibilityLabel("Search Help").padding(12)
        List(topics, selection: $selection) { topic in
          Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            .listItemTint(accent.color)
        }
        .listStyle(.sidebar)
      }
      .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    } detail: {
      if let topic = topics.first(where: { $0.id == selection }) {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
              Text(topic.title).font(.largeTitle).bold().accessibilityAddTraits(.isHeader)
              Text(topic.summary).foregroundStyle(.secondary)
            }
            ForEach(topic.sections) { section in
              VStack(alignment: .leading, spacing: 8) {
                Text(section.title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(section.body).fixedSize(horizontal: false, vertical: true)
                if let example = section.example {
                  Text(example).font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
              }
            }
          }
          .textSelection(.enabled)
          .frame(maxWidth: 640, alignment: .leading).padding(28)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(topic.id)
      } else {
        ContentUnavailableView.search(text: search)
      }
    }
    .frame(minWidth: 720, minHeight: 460)
    .focusedSceneValue(\.helpSearchAction, { searchFocused = true })
    .onChange(of: search) { _, _ in
      if !topics.contains(where: { $0.id == selection }) { selection = topics.first?.id }
    }
  }
}
