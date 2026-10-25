import AppKit
import SwiftUI

struct WindowLifecycleView: NSViewRepresentable {
  var state: AppState
  func makeCoordinator() -> Coordinator { Coordinator(state: state) }
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { [weak view] in
      view?.window?.delegate = context.coordinator
      view?.window?.tabbingMode = .disallowed
      // Preserve the window position saved by existing releases.
      view?.window?.setFrameAutosaveName("TapsterLibrary")
    }
    return view
  }
  func updateNSView(_ view: NSView, context: Context) {}

  @MainActor final class Coordinator: NSObject, NSWindowDelegate {
    let state: AppState
    init(state: AppState) { self.state = state }
    func windowShouldClose(_ sender: NSWindow) -> Bool { state.confirmUnsavedChanges() }
  }
}

extension AppState {
  func confirmUnsavedChanges() -> Bool {
    guard isDirty else { return true }
    let alert = NSAlert()
    alert.messageText = "Save changes to this snippet?"
    alert.informativeText = "Your changes have not been saved."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Discard Changes")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn: return save()
    case .alertSecondButtonReturn:
      discardDraft()
      return true
    default: return false
    }
  }
}
