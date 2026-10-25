import AppKit
import SwiftUI

/// Keep native List selection and keyboard handling, but draw its color in SwiftUI.
struct ThemedSelectionBridge: NSViewRepresentable {
  func makeNSView(context: Context) -> SelectionView { SelectionView() }

  func updateNSView(_ view: SelectionView, context: Context) {
    view.disableSystemHighlight()
  }

  final class SelectionView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      disableSystemHighlight()
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      disableSystemHighlight()
    }

    func disableSystemHighlight() {
      var ancestor = superview
      while let view = ancestor {
        if let table = view as? NSTableView {
          table.selectionHighlightStyle = .none
          return
        }
        ancestor = view.superview
      }
    }
  }
}
