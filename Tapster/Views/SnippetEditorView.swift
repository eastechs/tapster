import SwiftUI

struct SnippetEditorView: View {
  @Binding var draft: SnippetRecord
  @Bindable var state: AppState
  @State private var insertion: PlaceholderInsertion?
  @State private var placeholderSource: PlaceholderSource = .clipboard
  @State private var showingPlaceholder = false

  private var names: [String] { (try? TemplateParser.parse(draft.template).names) ?? [] }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .firstTextBaseline) {
          Text(draft.name.isEmpty ? "New Snippet" : draft.name)
            .font(.title.weight(.semibold)).lineLimit(2)
          Spacer()
          Toggle(isOn: $draft.isFavorite) {
            Image(systemName: draft.isFavorite ? "star.fill" : "star")
          }
          .toggleStyle(.button).help("Favorite snippet").accessibilityLabel("Favorite snippet")
        }
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
          GridRow {
            Text("Name").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            TextField("Snippet name", text: $draft.name).accessibilityLabel("Snippet name")
          }
          GridRow {
            Text("Keyword").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
              TextField("Optional keyword", text: $draft.keyword)
                .font(.system(.body, design: .monospaced)).frame(width: 220)
                .accessibilityLabel("Keyword")
              Text(keywordHelp).font(.caption).foregroundStyle(.secondary)
            }
          }
          GridRow {
            Text("Collection").foregroundStyle(.secondary)
            Picker("Collection", selection: $draft.collectionID) {
              Text("None").tag(UUID?.none)
              ForEach(state.store.collections) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden().frame(maxWidth: 220).fixedSize()
            .frame(width: 220, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .textFieldStyle(.roundedBorder)

        VStack(alignment: .leading, spacing: 10) {
          Text("Template").font(.headline)
          TemplateTextView(text: $draft.template, insertion: insertion)
            .frame(height: 160)
          ViewThatFits(in: .horizontal) {
            HStack {
              placeholderMenu
              Spacer(minLength: 12)
              braceHint
            }
            VStack(alignment: .leading, spacing: 8) {
              placeholderMenu
              braceHint
            }
          }
        }

        if !names.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.bottom, 4)
            Text("Placeholders").font(.headline)
            ForEach(names, id: \.self) { name in PlaceholderRow(name: name, draft: $draft) }
          }
        }

        if let error = state.draftError {
          Label(error, systemImage: "exclamationmark.circle")
            .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
        }
        VStack(alignment: .leading, spacing: 12) {
          Divider().padding(.bottom, 4)
          Text("Preview").font(.headline)
          Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
              Text("Clipboard").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
              TextField("Sample clipboard text", text: $state.sampleClipboard)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Sample clipboard text")
            }
            GridRow(alignment: .top) {
              Text("Result").foregroundStyle(.secondary).padding(.top, 10)
              Group {
                if let result = try? TemplateResolver.resolve(
                  draft, clipboard: state.sampleClipboard)
                {
                  Text(result.isEmpty ? " " : result).font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                } else {
                  Text("Complete the template and mappings to preview.").foregroundStyle(.secondary)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(10)
              .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
          }
        }
        ViewThatFits(in: .horizontal) {
          HStack {
            expansionToggle
            Spacer(minLength: 16)
            copyButton
          }
          VStack(alignment: .leading, spacing: 12) {
            expansionToggle
            copyButton
          }
        }
        if let message = state.engine.lastMessage {
          Text(message).font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(24)
      .frame(maxWidth: 760, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .frame(minWidth: 420)
    .controlSize(.regular)
    .sheet(isPresented: $showingPlaceholder) {
      PlaceholderSheet(source: placeholderSource, existingNames: names) { name, source in
        draft.placeholders.removeAll { $0.name == name }
        draft.placeholders.append(PlaceholderDefinition(name: name, source: source))
        insertion = PlaceholderInsertion(text: "{\(name)}")
      }
    }
  }

  private var placeholderMenu: some View {
    Menu {
      Button("Clipboard") {
        placeholderSource = .clipboard
        showingPlaceholder = true
      }
      Button("Date & Time") {
        placeholderSource = .dateTime
        showingPlaceholder = true
      }
    } label: {
      Label("Insert Placeholder", systemImage: "plus")
    }
    .fixedSize()
  }

  private var braceHint: some View {
    Text("{{ and }} insert literal braces").font(.caption).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var expansionToggle: some View {
    Toggle("Enable expansion", isOn: $draft.isEnabled)
      .help("Enable expansion for this snippet")
  }

  private var copyButton: some View {
    Button("Copy Expanded Text", action: state.copyExpandedText)
      .disabled(state.draftError != nil)
      .help("Resolves placeholders using the current clipboard")
  }

  private var keywordHelp: String {
    if !draft.keyword.isEmpty
      && state.store.snippets.contains(where: {
        $0.id != draft.id && $0.isEnabled && !$0.keyword.isEmpty
          && ($0.keyword.hasPrefix(draft.keyword) || draft.keyword.hasPrefix($0.keyword))
      })
    {
      return "Overlapping keywords use the delay in Settings → General."
    }
    return "Expands as you type. Leave empty to copy manually."
  }
}

private struct PlaceholderRow: View {
  var name: String
  @Binding var draft: SnippetRecord

  private var definition: PlaceholderDefinition? { draft.placeholders.first { $0.name == name } }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 18) {
        Text(name).font(.system(.body, design: .monospaced))
          .lineLimit(2).truncationMode(.middle).help(name).frame(
            maxWidth: .infinity, alignment: .leading)
        Picker(
          "Source for \(name)",
          selection: Binding<PlaceholderSource?>(get: { definition?.source }, set: setSource)
        ) {
          Text("Choose source…").tag(PlaceholderSource?.none)
          ForEach(PlaceholderSource.allCases) { Text($0.title).tag(Optional($0)) }
        }
        .labelsHidden().fixedSize()
        .frame(width: 180, alignment: .trailing)
      }
      if definition?.source == .dateTime {
        HStack {
          Text("Format").foregroundStyle(.secondary)
          TextField(
            "Date format",
            text: Binding(
              get: { definition?.dateFormat ?? "yyyy-MM-dd" },
              set: { value in
                if let index = draft.placeholders.firstIndex(where: { $0.name == name }) {
                  draft.placeholders[index].dateFormat = value
                }
              })
          ).textFieldStyle(.roundedBorder).frame(width: 140).accessibilityLabel(
            "Date format for \(name)")
          Text(dateExample).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var dateExample: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = definition?.dateFormat ?? "yyyy-MM-dd"
    return formatter.string(from: Date())
  }

  private func setSource(_ source: PlaceholderSource?) {
    guard let source else {
      draft.placeholders.removeAll { $0.name == name }
      return
    }
    if let index = draft.placeholders.firstIndex(where: { $0.name == name }) {
      draft.placeholders[index].source = source
    } else {
      draft.placeholders.append(PlaceholderDefinition(name: name, source: source))
    }
  }
}

private struct PlaceholderSheet: View {
  var source: PlaceholderSource
  var existingNames: [String]
  var insert: (String, PlaceholderSource) -> Void
  @State private var name = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Insert \(source.title) Placeholder").font(.headline)
      TextField("Placeholder name", text: $name).onSubmit(add)
      Text("Use letters, numbers, and underscores. You can reuse an existing name.")
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Insert", action: add).keyboardShortcut(.defaultAction).disabled(
          !TemplateParser.isValidName(name))
      }
    }
    .textFieldStyle(.roundedBorder)
    .padding(24).frame(width: 390)
    .onAppear { name = source == .clipboard ? "clipboard" : "today" }
  }
  private func add() {
    guard TemplateParser.isValidName(name) else { return }
    insert(name, source)
    dismiss()
  }
}
