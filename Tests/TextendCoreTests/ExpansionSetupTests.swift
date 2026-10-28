import AppKit
import XCTest

@testable import TextendCore

final class ExpansionSetupTests: XCTestCase {
  @MainActor func testAppStateUsesTheSameEngineAndPreferencesForSetup() throws {
    let h = SetupHarness()
    defer { h.stop() }
    let state = AppState(
      store: try LibraryStore(inMemory: true), preferences: h.preferences, engine: h.engine)
    XCTAssertTrue(state.expansionSetup.engine === state.engine)
    XCTAssertTrue(state.expansionSetup.isPresented)
    state.expansionSetup.finish()
    XCTAssertTrue(h.preferences.bool(forKey: "hasReviewedExpansionSetup"))
    XCTAssertFalse(h.engine.isEnabled)
  }

  @MainActor func testFreshInstallShowsSetupWithoutStartingExpansion() {
    let h = SetupHarness()
    defer { h.stop() }
    let setup = h.makeSetup()
    XCTAssertTrue(setup.isPresented)
    XCTAssertFalse(h.engine.isEnabled)
    XCTAssertFalse(h.engine.hasRequiredPermissions)
    XCTAssertEqual(h.engine.status, .paused)
    XCTAssertEqual(h.listenerAttempts, 0)
    XCTAssertNil(h.preferences.object(forKey: "expansionEnabled"))
  }

  @MainActor func testExistingEnabledAndPausedPreferencesDoNotTriggerFirstRunSetup() {
    for enabled in [true, false] {
      let h = SetupHarness()
      defer { h.stop() }
      h.preferences.set(enabled, forKey: "expansionEnabled")
      let setup = h.makeSetup()
      XCTAssertFalse(setup.isPresented)
      XCTAssertEqual(h.engine.isEnabled, enabled)
    }
  }

  @MainActor func testSkipIsRememberedAndSettingsCanReopenSetup() {
    let h = SetupHarness()
    defer { h.stop() }
    let setup = h.makeSetup()
    setup.finish()
    XCTAssertFalse(setup.isPresented)
    XCTAssertFalse(h.engine.isEnabled)
    XCTAssertNil(h.preferences.object(forKey: "expansionEnabled"))
    let reopened = h.makeSetup()
    XCTAssertFalse(reopened.isPresented)
    reopened.show()
    XCTAssertTrue(reopened.isPresented)
  }

  @MainActor func testPermissionChangesAreObservedWhilePausedAndEnableRequiresBothGrants() {
    let h = SetupHarness()
    defer { h.stop() }
    let setup = h.makeSetup()
    XCTAssertFalse(setup.enableExpansion())
    h.accessibility = true
    h.engine.refresh()
    XCTAssertTrue(h.engine.accessibilityGranted)
    XCTAssertFalse(h.engine.hasRequiredPermissions)
    XCTAssertFalse(setup.enableExpansion())
    XCTAssertTrue(setup.isPresented)
    XCTAssertFalse(h.preferences.bool(forKey: "hasReviewedExpansionSetup"))
    XCTAssertEqual(h.listenerAttempts, 0)

    h.posting = true
    h.engine.refresh()
    XCTAssertTrue(h.engine.hasRequiredPermissions)
    XCTAssertFalse(h.engine.isEnabled, "Granting access alone must not enable expansion.")
    // Recheck when Continue is clicked, even if permission changed since the last timer tick.
    h.accessibility = false
    XCTAssertFalse(setup.enableExpansion())
    h.accessibility = true
    XCTAssertTrue(setup.enableExpansion())
    XCTAssertTrue(h.engine.isEnabled)
    XCTAssertTrue(h.preferences.bool(forKey: "expansionEnabled"))
    XCTAssertTrue(h.preferences.bool(forKey: "hasReviewedExpansionSetup"))
    XCTAssertFalse(setup.isPresented)
    XCTAssertEqual(h.listenerAttempts, 1)
  }

  @MainActor func testExistingPermissionStillRequiresExplicitEnableOnFreshInstall() {
    let h = SetupHarness()
    defer { h.stop() }
    h.accessibility = true
    h.posting = true
    let setup = h.makeSetup()
    XCTAssertTrue(setup.isPresented)
    XCTAssertTrue(h.engine.hasRequiredPermissions)
    XCTAssertFalse(h.engine.isEnabled)
    XCTAssertEqual(h.listenerAttempts, 0)
  }
}

@MainActor private final class SetupHarness {
  private let suite = "textend-setup-tests." + UUID().uuidString
  lazy var preferences = UserDefaults(suiteName: suite)!
  var accessibility = false
  var posting = false
  var listenerAttempts = 0
  lazy var engine = ExpansionEngine(
    preferences: preferences, workspaceCenter: NotificationCenter(),
    accessibility: { [unowned self] in accessibility },
    postEventAccess: { [unowned self] in posting },
    secureInput: { false }, supportsInputSource: { true },
    makeEventTap: { [unowned self] _ in
      listenerAttempts += 1
      return nil
    })

  func makeSetup() -> ExpansionSetup {
    engine.start()
    return ExpansionSetup(engine: engine, preferences: preferences)
  }

  func stop() {
    engine.stop()
    preferences.removePersistentDomain(forName: suite)
  }
}
