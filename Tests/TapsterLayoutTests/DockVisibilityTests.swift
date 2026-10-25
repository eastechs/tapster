import AppKit
import XCTest

@testable import TapsterLayout

final class DockVisibilityTests: XCTestCase {
  @MainActor func testTogglingPreferenceDoesNotChangePolicyOrOpenWindows() {
    let harness = Harness()
    defer { harness.stop() }
    let library = harness.makeWindow()
    let settings = harness.makeWindow()
    let frames = harness.windows.map(\.frame)
    harness.controller.start(alwaysVisible: true)

    for value in [false, true, false, true, false] {
      XCTAssertTrue(harness.controller.setAlwaysVisible(value))
      XCTAssertEqual(harness.policy, .regular)
      XCTAssertTrue(library.isVisible)
      XCTAssertTrue(settings.isVisible)
      XCTAssertEqual(harness.windows.map(\.frame), frames)
      XCTAssertTrue(harness.windows.allSatisfy(\.canHide))
    }
    XCTAssertTrue(harness.changes.isEmpty, "An open window must prevent any policy transition.")
  }

  @MainActor func testOnlyLastCloseHidesDockAndReopeningRestoresIt() async throws {
    let harness = Harness()
    defer { harness.stop() }
    let library = harness.makeWindow()
    let settings = harness.makeWindow()
    harness.controller.start(alwaysVisible: false)

    library.close()
    try await settle()
    XCTAssertEqual(harness.policy, .regular)
    XCTAssertTrue(settings.isVisible)
    settings.close()
    // The willClose observer must not demote the app before the close finishes.
    XCTAssertTrue(harness.changes.isEmpty)
    try await settle()
    XCTAssertEqual(harness.changes, [.accessory])

    library.orderFront(nil)
    library.update()
    try await settle()
    XCTAssertEqual(harness.changes, [.accessory, .regular])
    XCTAssertTrue(library.isVisible)
    XCTAssertFalse(settings.isVisible)
  }

  @MainActor func testAlwaysVisibleKeepsDockWithoutWindows() async throws {
    let harness = Harness()
    defer { harness.stop() }
    let window = harness.makeWindow()
    harness.controller.start(alwaysVisible: true)
    window.close()
    try await settle()
    XCTAssertTrue(harness.changes.isEmpty)
    XCTAssertTrue(harness.controller.setAlwaysVisible(false))
    XCTAssertEqual(harness.policy, .accessory)
    XCTAssertTrue(harness.controller.setAlwaysVisible(true))
    XCTAssertEqual(harness.policy, .regular)
  }

  @MainActor func testHiddenWindowsKeepDockUntilClosed() async throws {
    let harness = Harness()
    defer { harness.stop() }
    let window = harness.makeWindow()
    harness.controller.start(alwaysVisible: false)
    harness.isHidden = true
    window.orderOut(nil)
    NotificationCenter.default.post(name: NSApplication.didHideNotification, object: nil)
    try await settle()
    XCTAssertEqual(harness.policy, .regular)
    window.close()
    try await settle()
    XCTAssertEqual(harness.policy, .accessory)
  }

  @MainActor func testMinimizedWindowsKeepDock() async throws {
    let harness = Harness()
    defer { harness.stop() }
    let window = harness.makeWindow()
    harness.controller.start(alwaysVisible: false)
    window.miniaturize(nil)
    try await settle()
    XCTAssertTrue(window.isMiniaturized)
    XCTAssertEqual(harness.policy, .regular)
    XCTAssertTrue(harness.changes.isEmpty)
    window.close()
    try await settle()
    XCTAssertEqual(harness.policy, .accessory)
  }

  @MainActor func testTransientWindowsAndRejectedPolicyChange() {
    let harness = Harness()
    defer { harness.stop() }
    _ = harness.makeWindow(titled: false)
    harness.controller.start(alwaysVisible: false)
    XCTAssertEqual(harness.policy, .accessory, "A menu or tooltip must not keep the Dock icon.")
    harness.rejectChanges = true
    XCTAssertFalse(harness.controller.setAlwaysVisible(true))
    harness.rejectChanges = false
    harness.controller.start(alwaysVisible: false)
    XCTAssertEqual(harness.policy, .accessory)
  }

  @MainActor private func settle() async throws {
    try await Task.sleep(for: .milliseconds(60))
  }
}

@MainActor private final class Harness {
  var windows: [NSWindow] = []
  var isHidden = false
  var policy: NSApplication.ActivationPolicy = .regular
  var changes: [NSApplication.ActivationPolicy] = []
  var rejectChanges = false
  lazy var controller = DockVisibility(
    windows: { [weak self] in self?.windows ?? [] },
    appIsHidden: { [weak self] in self?.isHidden ?? false },
    currentPolicy: { [weak self] in self?.policy ?? .regular },
    applyPolicy: { [weak self] policy in
      guard let self, !self.rejectChanges else { return false }
      self.changes.append(policy)
      self.policy = policy
      return true
    })

  func makeWindow(titled: Bool = true) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 100, height: 100),
      styleMask: titled ? [.titled, .closable, .miniaturizable] : [.borderless],
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    windows.append(window)
    window.orderFront(nil)
    return window
  }

  func stop() {
    controller.stop()
    for window in windows { window.close() }
  }
}
