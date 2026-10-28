import Foundation
import Observation

@MainActor @Observable final class ExpansionSetup {
  let engine: ExpansionEngine
  private let preferences: UserDefaults
  var isPresented: Bool

  init(engine: ExpansionEngine, preferences: UserDefaults = .standard) {
    self.engine = engine
    self.preferences = preferences
    // An existing expansion preference means the user already chose how to use the app.
    isPresented =
      !preferences.bool(forKey: "hasReviewedExpansionSetup")
      && preferences.object(forKey: "expansionEnabled") == nil
  }

  func show() {
    engine.refresh()
    isPresented = true
  }

  @discardableResult func enableExpansion() -> Bool {
    engine.refresh()
    guard engine.hasRequiredPermissions else { return false }
    engine.setEnabled(true)
    finish()
    return true
  }

  func finish() {
    preferences.set(true, forKey: "hasReviewedExpansionSetup")
    isPresented = false
  }
}
