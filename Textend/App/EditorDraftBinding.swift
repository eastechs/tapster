import SwiftUI

extension AppState {
  func editorBinding(for snapshot: SnippetRecord) -> Binding<SnippetRecord> {
    Binding(
      get: {
        // SwiftUI can read the departing editor while its replacement is being laid out.
        guard let current = self.draft, current.id == snapshot.id else { return snapshot }
        return current
      },
      set: { value in
        // Late text-view callbacks must not restore a cleared draft or overwrite another snippet.
        guard self.draft?.id == snapshot.id, value.id == snapshot.id else { return }
        self.draft = value
      })
  }
}
