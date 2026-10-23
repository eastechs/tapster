import SwiftUI

struct SnippetDetailView: View {
  @Bindable var state: AppState

  var body: some View {
    Group {
      if let draft = state.draft {
        SnippetEditorView(draft: state.editorBinding(for: draft), state: state)
          .id(draft.id)
      } else {
        ContentUnavailableView {
          Label("Your words, a shortcut away", systemImage: "text.insert")
        } description: {
          Text("Select a snippet or create a new one.")
        } actions: {
          Button("New Snippet", action: state.newSnippet)
        }
      }
    }
    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct SnippetPreviewPanel: View {
  @Bindable var state: AppState

  var body: some View {
    Group {
      if let draft = state.draft {
        SnippetPreviewView(draft: draft, state: state)
      } else {
        ContentUnavailableView(
          "Preview", systemImage: "text.alignleft",
          description: Text("Select a snippet to preview it."))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
