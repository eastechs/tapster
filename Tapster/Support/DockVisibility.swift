import AppKit

/// Keeps the app regular while it owns open windows. Accessory mode is only
/// entered after the last window closes, so Dock changes never hide an editor.
@MainActor final class DockVisibility {
  static let shared = DockVisibility()

  private let windows: @MainActor () -> [NSWindow]
  private let appIsHidden: @MainActor () -> Bool
  private let currentPolicy: @MainActor () -> NSApplication.ActivationPolicy
  private let applyPolicy: @MainActor (NSApplication.ActivationPolicy) -> Bool
  private let notifications: NotificationCenter
  private let openWindows = NSHashTable<NSWindow>.weakObjects()
  private var observers: [NSObjectProtocol] = []
  private var refreshScheduled = false
  private var alwaysVisible = true

  init(
    windows: @escaping @MainActor () -> [NSWindow] = { NSApplication.shared.windows },
    appIsHidden: @escaping @MainActor () -> Bool = { NSApplication.shared.isHidden },
    currentPolicy: @escaping @MainActor () -> NSApplication.ActivationPolicy = {
      NSApplication.shared.activationPolicy()
    },
    applyPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Bool = {
      NSApplication.shared.setActivationPolicy($0)
    },
    notifications: NotificationCenter = .default
  ) {
    self.windows = windows
    self.appIsHidden = appIsHidden
    self.currentPolicy = currentPolicy
    self.applyPolicy = applyPolicy
    self.notifications = notifications
  }

  func start(alwaysVisible: Bool) {
    self.alwaysVisible = alwaysVisible
    guard observers.isEmpty else {
      refresh()
      return
    }
    for name in [
      NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification,
      NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
      NSWindow.didChangeOcclusionStateNotification,
      NSApplication.didHideNotification, NSApplication.didUnhideNotification,
      NSWindow.willCloseNotification,
    ] {
      observers.append(
        notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
          MainActor.assumeIsolated {
            guard let self else { return }
            if name == NSWindow.willCloseNotification, let window = note.object as? NSWindow {
              self.openWindows.remove(window)
            }
            self.scheduleRefresh()
          }
        })
    }
    refresh()
  }

  func stop() {
    for observer in observers { notifications.removeObserver(observer) }
    observers.removeAll()
    openWindows.removeAllObjects()
  }

  @discardableResult func setAlwaysVisible(_ value: Bool) -> Bool {
    let previous = alwaysVisible
    alwaysVisible = value
    guard refresh() else {
      alwaysVisible = previous
      return false
    }
    return true
  }

  @discardableResult private func refresh() -> Bool {
    // Hide is not Close. Keep the Dock available for hidden or minimized
    // windows so the user can bring them back through normal macOS controls.
    if !appIsHidden() { openWindows.removeAllObjects() }
    for window in windows()
    where window.styleMask.contains(.titled) && (window.isVisible || window.isMiniaturized) {
      openWindows.add(window)
    }
    let policy: NSApplication.ActivationPolicy =
      alwaysVisible || !openWindows.allObjects.isEmpty ? .regular : .accessory
    return currentPolicy() == policy || applyPolicy(policy)
  }

  private func scheduleRefresh() {
    guard !refreshScheduled else { return }
    refreshScheduled = true
    // willClose arrives before isVisible changes. Re-read the windows after
    // that close finishes, also coalescing the notifications from a new window.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.refreshScheduled = false
      guard !self.observers.isEmpty else { return }
      self.refresh()
    }
  }
}
