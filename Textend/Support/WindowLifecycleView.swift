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
    alert.messageText = "Save changes to this item?"
    alert.informativeText = "Your changes have not been saved."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Discard Changes")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
      guard save() else {
        let failure = NSAlert()
        failure.messageText = "Couldn’t Save Changes"
        failure.informativeText = errorMessage ?? "Your changes have not been saved."
        errorMessage = nil
        failure.runModal()
        return false
      }
      return true
    case .alertSecondButtonReturn:
      discardDraft()
      return true
    default: return false
    }
  }
}
