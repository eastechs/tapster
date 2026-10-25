import AppKit
import SwiftUI

struct PlaceholderInsertion: Identifiable {
  var id = UUID()
  var text: String
}

struct TemplateTextView: NSViewRepresentable {
  @Binding var text: String
  @Environment(\.textendAccent) private var accent
  var insertion: PlaceholderInsertion?

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    let view = NSTextView()
    view.isRichText = false
    view.allowsUndo = true
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.isAutomaticSpellingCorrectionEnabled = false
    view.isContinuousSpellCheckingEnabled = false
    view.isGrammarCheckingEnabled = false
    view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    view.textColor = .textColor
    view.backgroundColor = .textBackgroundColor
    view.textContainerInset = NSSize(width: 14, height: 14)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.textContainer?.widthTracksTextView = true
    view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    view.delegate = context.coordinator
    view.setAccessibilityLabel("Snippet template")
    scroll.documentView = view
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let view = scroll.documentView as? NSTextView else { return }
    let needsHighlight = view.string != text || context.coordinator.lastAccent != accent
    if view.string != text {
      let selection = view.selectedRange()
      view.string = text
      view.setSelectedRange(
        NSRange(location: min(selection.location, (text as NSString).length), length: 0))
    }
    if needsHighlight { context.coordinator.highlight(view) }
    if let insertion, context.coordinator.lastInsertion != insertion.id {
      context.coordinator.lastInsertion = insertion.id
      view.window?.makeFirstResponder(view)
      view.insertText(insertion.text, replacementRange: view.selectedRange())
    }
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: TemplateTextView
    var lastInsertion: UUID?
    var lastAccent: AppAccent?
    init(_ parent: TemplateTextView) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      parent.text = view.string
      highlight(view)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      guard let view = notification.object as? NSTextView else { return }
      view.typingAttributes = [
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.textColor,
      ]
    }

    func highlight(_ view: NSTextView) {
      guard let storage = view.textStorage else { return }
      lastAccent = parent.accent
      let range = NSRange(location: 0, length: storage.length)
      storage.beginEditing()
      storage.addAttributes(
        [
          .foregroundColor: NSColor.textColor,
          .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        ], range: range)
      storage.removeAttribute(.backgroundColor, range: range)
      if let expression = try? NSRegularExpression(
        pattern: "(?<!\\{)\\{[\\p{L}_][\\p{L}\\p{N}_]*\\}(?!\\})")
      {
        for match in expression.matches(in: view.string, range: range) {
          storage.addAttributes(
            [
              .foregroundColor: parent.accent.nsColor,
              .backgroundColor: parent.accent.nsColor.withAlphaComponent(0.1),
            ], range: match.range)
        }
      }
      storage.endEditing()
    }
  }
}
