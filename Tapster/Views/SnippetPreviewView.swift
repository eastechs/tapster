import SwiftUI

struct SnippetPreviewView: View {
  var draft: SnippetRecord
  @Bindable var state: AppState
  @Environment(\.textendAccent) private var accent

  var body: some View {
    let result = try? TemplateResolver.resolveExpansion(draft, clipboard: state.sampleClipboard)
    let unresolvedMessage =
      state.copyError == nil && state.sampleClipboard.isEmpty
      ? "Enter sample clipboard text to preview."
      : "Complete the template and mappings to preview."
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Preview").font(.headline)
        VStack(alignment: .leading, spacing: 8) {
          Text("Sample clipboard").foregroundStyle(.secondary)
          TextField("Sample clipboard text", text: $state.sampleClipboard, axis: .vertical)
            .lineLimit(3...6)
            .textFieldStyle(SnippetInputStyle())
            .accessibilityLabel("Sample clipboard text")
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Result").foregroundStyle(.secondary)
          Group {
            if let result {
              if let index = result.cursorIndex {
                Text(markedPreview(result, at: index))
                  .font(.system(.body, design: .monospaced))
              } else {
                Text(result.text.isEmpty ? " " : result.text)
                  .font(.system(.body, design: .monospaced))
                  .textSelection(.enabled)
              }
            } else {
              Text(unresolvedMessage)
                .foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
          .padding(12)
          .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Preview result")
          .accessibilityValue(result.map(previewDescription) ?? unresolvedMessage)
          if result?.cursorUTF16Offset != nil {
            Text("│ marks the caret position.").font(.caption).foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .contain)
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Button("Copy Expanded Text", action: state.copyExpandedText)
            .disabled(state.copyError != nil)
            .help("Resolves placeholders using the current clipboard")
          Text(
            result?.cursorUTF16Offset == nil
              ? "Uses your current clipboard."
              : "Uses your current clipboard. Copies text only; caret placement applies when expanding."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.quaternary.opacity(0.12))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Snippet preview")
  }

  private func markedPreview(_ result: ResolvedExpansion, at index: String.Index)
    -> AttributedString
  {
    var text = AttributedString(String(result.text[..<index]))
    var marker = AttributedString("│")
    marker.foregroundColor = accent.color
    text.append(marker)
    text.append(AttributedString(String(result.text[index...])))
    return text
  }

  private func previewDescription(_ result: ResolvedExpansion) -> String {
    guard let index = result.cursorIndex else { return result.text }
    return "\(result.text). Caret at character \(result.text[..<index].count + 1)."
  }
}
