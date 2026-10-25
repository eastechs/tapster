import AppKit

/// Chooses one activation policy before launch completes. Window activity and
/// preference edits never change it; the next launch applies a new preference.
@MainActor final class DockVisibility {
  static let shared = DockVisibility()

  private let currentPolicy: @MainActor () -> NSApplication.ActivationPolicy
  private let applyPolicy: @MainActor (NSApplication.ActivationPolicy) -> Bool
  private var startupResult: Bool?

  init(
    currentPolicy: @escaping @MainActor () -> NSApplication.ActivationPolicy = {
      NSApplication.shared.activationPolicy()
    },
    applyPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Bool = {
      NSApplication.shared.setActivationPolicy($0)
    }
  ) {
    self.currentPolicy = currentPolicy
    self.applyPolicy = applyPolicy
  }

  @discardableResult func start(showInDock: Bool) -> Bool {
    if let startupResult { return startupResult }
    let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
    let result = currentPolicy() == policy || applyPolicy(policy)
    startupResult = result
    return result
  }

  func requiresRestart(showInDock: Bool) -> Bool {
    currentPolicy() != (showInDock ? .regular : .accessory)
  }
}
