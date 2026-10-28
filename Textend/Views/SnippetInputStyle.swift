import SwiftUI

struct SnippetInputStyle: TextFieldStyle {
  private var requestedFocus: FocusState<Bool>.Binding?
  @FocusState private var localFocus: Bool

  init(focus: FocusState<Bool>.Binding? = nil) { requestedFocus = focus }

  private var focus: FocusState<Bool>.Binding { requestedFocus ?? $localFocus }

  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .textFieldStyle(.plain)
      .focused(focus)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .snippetInputSurface(isFocused: focus.wrappedValue)
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
