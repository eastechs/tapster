import AppKit
import XCTest

@testable import TapsterLayout

final class DockVisibilityTests: XCTestCase {
  @MainActor func testMenuBarModeDoesNotReactToWindowsOrPreferenceChanges() {
    let harness = Harness(policy: .accessory)
    XCTAssertTrue(harness.controller.start(showInDock: false))
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 100, height: 100),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    for _ in 0..<3 {
      window.orderFront(nil)
      window.update()
      XCTAssertTrue(window.isVisible)
      window.close()
      NotificationCenter.default.post(name: NSApplication.didHideNotification, object: nil)
      NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: nil)
      XCTAssertEqual(harness.policy, .accessory)
    }
    XCTAssertTrue(harness.controller.requiresRestart(showInDock: true))
    XCTAssertFalse(harness.controller.requiresRestart(showInDock: false))
    XCTAssertTrue(harness.controller.start(showInDock: true))
    XCTAssertTrue(
      harness.changes.isEmpty, "Even a repeated launch callback must not switch policy.")
  }

  @MainActor func testDockModeIsAppliedOnceAndCanBeChangedOnNextLaunch() {
    let harness = Harness(policy: .accessory)
    XCTAssertTrue(harness.controller.start(showInDock: true))
    XCTAssertEqual(harness.changes, [.regular])
    XCTAssertFalse(harness.controller.requiresRestart(showInDock: true))
    XCTAssertTrue(harness.controller.requiresRestart(showInDock: false))
    XCTAssertTrue(harness.controller.start(showInDock: false))
    XCTAssertEqual(harness.changes, [.regular])
    let nextLaunch = DockVisibility(
      currentPolicy: { harness.policy },
      applyPolicy: {
        harness.policy = $0
        return true
      })
    XCTAssertTrue(nextLaunch.start(showInDock: false))
    XCTAssertEqual(harness.policy, .accessory)
  }

  @MainActor func testRejectedStartupPolicyStaysPendingWithoutAutomaticRetries() {
    let harness = Harness(policy: .accessory)
    harness.rejectChanges = true
    XCTAssertFalse(harness.controller.start(showInDock: true))
    XCTAssertTrue(harness.controller.requiresRestart(showInDock: true))
    harness.rejectChanges = false
    XCTAssertFalse(harness.controller.start(showInDock: true))
    XCTAssertEqual(harness.policy, .accessory)
  }
}

@MainActor private final class Harness {
  var policy: NSApplication.ActivationPolicy
  var changes: [NSApplication.ActivationPolicy] = []
  var rejectChanges = false
  lazy var controller = DockVisibility(
    currentPolicy: { [weak self] in self?.policy ?? .accessory },
    applyPolicy: { [weak self] policy in
      guard let self, !self.rejectChanges else { return false }
      self.changes.append(policy)
      self.policy = policy
      return true
    })

  init(policy: NSApplication.ActivationPolicy) { self.policy = policy }
}
