import SwiftUI

struct SnippetInputStyle: TextFieldStyle {
  @FocusState private var isFocused: Bool

  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .textFieldStyle(.plain)
      .focused($isFocused)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .snippetInputSurface(isFocused: isFocused)
  }
}

extension View {
  func snippetInputSurface(isFocused: Bool = false) -> some View {
    modifier(SnippetInputSurface(isFocused: isFocused))
  }
}

private struct SnippetInputSurface: ViewModifier {
  var isFocused: Bool
  @Environment(\.textendAccent) private var accent

  func body(content: Content) -> some View {
    content
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(
            isFocused ? accent.color : Color(nsColor: .separatorColor),
            lineWidth: isFocused ? 2 : 1
          )
          .allowsHitTesting(false)
      }
  }
}
