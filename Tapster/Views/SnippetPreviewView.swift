import SwiftUI

struct SnippetPreviewView: View {
  var draft: SnippetRecord
  @Bindable var state: AppState

  var body: some View {
    let result = try? TemplateResolver.resolve(draft, clipboard: state.sampleClipboard)
    let unresolvedMessage = "Complete the template and mappings to preview."
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
              Text(result.isEmpty ? " " : result)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
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
          .accessibilityValue(result ?? unresolvedMessage)
        }
        .accessibilityElement(children: .contain)
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Button("Copy Expanded Text", action: state.copyExpandedText)
            .disabled(state.copyError != nil)
            .help("Resolves placeholders using the current clipboard")
          Text("Uses your current clipboard.")
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
}
