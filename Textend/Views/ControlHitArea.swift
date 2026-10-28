import SwiftUI

extension View {
  /// Apply inside a control's label, after sizing and padding, so its entire area responds.
  func controlHitArea(minWidth: CGFloat = 24, minHeight: CGFloat = 24) -> some View {
    frame(minWidth: minWidth, minHeight: minHeight)
      .contentShape(.interaction, Rectangle())
  }
}
