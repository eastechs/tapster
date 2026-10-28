import AppKit
import XCTest

@testable import TextendCore

final class ExpansionLifecycleTests: XCTestCase {
  @MainActor func testPreviewStartsPausedAndCanResumeWithoutChangingSavedPreferenceOnLaunch() throws
  {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    XCTAssertTrue(h.engine.isEnabled)
    h.engine.start(initiallyPaused: true)
    h.engine.start()
    h.post(NSWorkspace.didWakeNotification)
    h.engine.refresh()

    XCTAssertFalse(h.engine.isEnabled)
    XCTAssertEqual(h.engine.status, .paused)
    XCTAssertTrue(h.savedEnabled)
    XCTAssertTrue(h.taps.isEmpty)

    h.engine.setEnabled(true)
    h.engine.start(initiallyPaused: true)
    XCTAssertTrue(h.engine.isEnabled)
    XCTAssertEqual(h.engine.status, .active)
    XCTAssertEqual(h.taps.count, 1)

    let tap = try XCTUnwrap(h.taps.last)
    h.engine.setEnabled(false)
    XCTAssertFalse(h.engine.isEnabled)
    XCTAssertFalse(h.savedEnabled)
    XCTAssertEqual(h.engine.status, .paused)
    XCTAssertEqual(tap.invalidations, 1)
  }

  @MainActor func testResumingPreviewReportsMissingPermissionThenRecovers() {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.accessibility = false
    h.engine.start(initiallyPaused: true)
    XCTAssertFalse(h.engine.isEnabled)
    XCTAssertEqual(h.engine.status, .paused)

    h.engine.setEnabled(true)
    XCTAssertTrue(h.engine.isEnabled)
    XCTAssertEqual(h.engine.status, .permission)
    XCTAssertTrue(h.taps.isEmpty)

    h.accessibility = true
    h.engine.refresh()
    XCTAssertEqual(h.engine.status, .active)
    XCTAssertEqual(h.taps.count, 1)
  }

  @MainActor func testWakeReplacesAnApparentlyHealthyListener() throws {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.engine.start()
    let original = try XCTUnwrap(h.taps.last)

    // Reproduce a tap that still reports enabled after wake but delivers no keys.
    h.post(NSWorkspace.didWakeNotification)

    XCTAssertEqual(original.invalidations, 1)
    XCTAssertEqual(h.taps.count, 2)
    XCTAssertEqual(h.engine.status, .active)
  }

  @MainActor func testSleepSuspendsMonitoringUntilWake() throws {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.engine.start()
    let original = try XCTUnwrap(h.taps.last)
    h.post(NSWorkspace.willSleepNotification)
    h.engine.refresh()
    h.post(NSWorkspace.didActivateApplicationNotification)
    h.engine.setEnabled(true)

    XCTAssertEqual(original.invalidations, 1)
    XCTAssertEqual(h.taps.count, 1)
    XCTAssertEqual(h.engine.status, .paused)
    h.post(NSWorkspace.didWakeNotification)
    XCTAssertEqual(h.taps.count, 2)
    XCTAssertEqual(h.engine.status, .active)
  }

  @MainActor func testWakeAndSessionReturnMustBothFinishBeforeMonitoringResumes() {
    for wakeFirst in [true, false] {
      let h = ExpansionLifecycleHarness()
      defer { h.stop() }
      h.engine.start()
      h.post(NSWorkspace.sessionDidResignActiveNotification)
      h.post(NSWorkspace.willSleepNotification)
      let wake = NSWorkspace.didWakeNotification
      let session = NSWorkspace.sessionDidBecomeActiveNotification

      h.post(wakeFirst ? wake : session)
      h.post(NSWorkspace.screensDidWakeNotification)
      h.engine.refresh()
      XCTAssertEqual(h.engine.status, .paused)
      XCTAssertEqual(h.taps.count, 1)

      h.post(wakeFirst ? session : wake)
      XCTAssertEqual(h.engine.status, .active)
      XCTAssertEqual(h.taps.count, 2)
    }
  }

  @MainActor func testDisplayWakeAndSessionReturnReplaceExistingTaps() throws {
    for notification in [
      NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      let h = ExpansionLifecycleHarness()
      defer { h.stop() }
      h.engine.start()
      let original = try XCTUnwrap(h.taps.last)
      h.post(notification)
      XCTAssertEqual(original.invalidations, 1)
      XCTAssertEqual(h.taps.count, 2)
      XCTAssertEqual(h.engine.status, .active)
    }
  }

  @MainActor func testInvalidPortIsReplacedEvenWhenReportedEnabled() throws {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.engine.start()
    let original = try XCTUnwrap(h.taps.last)
    original.isValid = false
    h.engine.refresh()

    XCTAssertEqual(original.enables, 1)
    XCTAssertEqual(original.invalidations, 1)
    XCTAssertEqual(h.taps.count, 2)
    XCTAssertEqual(h.engine.status, .active)
  }

  @MainActor func testDisabledListenerIsReenabledWithoutReplacingIt() throws {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.engine.start()
    let original = try XCTUnwrap(h.taps.last)
    original.isEnabled = false
    h.engine.refresh()

    XCTAssertEqual(original.enables, 2)
    XCTAssertTrue(original.isEnabled)
    XCTAssertEqual(h.taps.count, 1)
    XCTAssertEqual(h.engine.status, .active)
  }

  @MainActor func testListenerIsReplacedWhenReenablingFails() throws {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.engine.start()
    let original = try XCTUnwrap(h.taps.last)
    original.isEnabled = false
    original.canEnable = false
    h.engine.refresh()

    XCTAssertEqual(original.invalidations, 1)
    XCTAssertEqual(h.taps.count, 2)
    XCTAssertEqual(h.engine.status, .active)
  }

  @MainActor func testDisableCallbacksRecoverEvenWithGeneratedEventMarker() throws {
    for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
      let h = ExpansionLifecycleHarness()
      defer { h.stop() }
      h.engine.start()
      let original = try XCTUnwrap(h.taps.last)
      original.isEnabled = false
      let event = try XCTUnwrap(CGEvent(source: nil))
      event.setIntegerValueField(.eventSourceUserData, value: TextInsertionService.eventMarker)
      original.receive(type, event)

      XCTAssertTrue(original.isEnabled)
      XCTAssertEqual(original.enables, 2)
      XCTAssertEqual(h.taps.count, 1)
    }
  }

  @MainActor func testFailedWakeInstallationRetriesWithoutRestarting() {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.engine.start()
    h.canCreate = false
    h.post(NSWorkspace.didWakeNotification)
    XCTAssertEqual(h.engine.status, .unavailable)
    XCTAssertTrue(h.engine.accessibilityGranted)
    h.engine.refresh()
    XCTAssertEqual(h.engine.status, .unavailable)

    h.canCreate = true
    h.engine.refresh()
    XCTAssertEqual(h.taps.count, 2)
    XCTAssertEqual(h.engine.status, .active)
    XCTAssertNil(h.engine.lastMessage)
  }

  @MainActor func testNewButDisabledListenerIsNotReportedActive() throws {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.canEnableNewTap = false
    h.engine.start()
    let original = try XCTUnwrap(h.taps.last)
    XCTAssertEqual(h.engine.status, .unavailable)
    XCTAssertEqual(original.invalidations, 1)

    h.canEnableNewTap = true
    h.engine.refresh()
    XCTAssertEqual(h.engine.status, .active)
    XCTAssertEqual(h.taps.count, 2)
  }

  @MainActor func testRecoveryRespectsPausePermissionsSecureInputAndComposition() {
    for reason in ["pause", "accessibility", "posting", "secure", "composition"] {
      let h = ExpansionLifecycleHarness()
      defer { h.stop() }
      h.engine.start()
      let expected: ExpansionEngine.Status
      switch reason {
      case "pause":
        h.engine.setEnabled(false)
        expected = .paused
      case "accessibility":
        h.accessibility = false
        expected = .permission
      case "posting":
        h.posting = false
        expected = .permission
      case "secure":
        h.secure = true
        expected = .secure
      default:
        h.supportsInput = false
        expected = .composition
      }
      h.post(NSWorkspace.didWakeNotification)
      h.engine.refresh()
      XCTAssertEqual(h.engine.status, expected, reason)
      XCTAssertEqual(h.taps.count, 1, reason)

      h.accessibility = true
      h.posting = true
      h.secure = false
      h.supportsInput = true
      h.engine.setEnabled(true)
      XCTAssertEqual(h.engine.status, .active, reason)
      XCTAssertEqual(h.taps.count, 2, reason)
    }
  }

  @MainActor func testStartStopAndNormalRefreshDoNotDuplicateListeners() throws {
    let h = ExpansionLifecycleHarness()
    defer { h.stop() }
    h.engine.setEnabled(true)
    XCTAssertTrue(h.taps.isEmpty)
    h.engine.start()
    h.engine.start()
    h.engine.refresh()
    h.post(NSWorkspace.didActivateApplicationNotification)
    XCTAssertEqual(h.taps.count, 1)
    h.post(NSWorkspace.didWakeNotification)
    XCTAssertEqual(h.taps.count, 2)

    let last = try XCTUnwrap(h.taps.last)
    h.engine.stop()
    h.engine.stop()
    h.engine.refresh()
    h.engine.setEnabled(true)
    h.post(NSWorkspace.didWakeNotification)
    XCTAssertEqual(h.engine.status, .paused)
    XCTAssertEqual(last.invalidations, 1)
    XCTAssertEqual(h.taps.count, 2)
    h.engine.start()
    XCTAssertEqual(h.engine.status, .active)
    XCTAssertEqual(h.taps.count, 3)
  }
}

@MainActor private final class ExpansionLifecycleHarness {
  let center = NotificationCenter()
  private let suite = "textend-expansion-tests." + UUID().uuidString
  private lazy var preferences = UserDefaults(suiteName: suite)!
  var savedEnabled: Bool { preferences.bool(forKey: "expansionEnabled") }
  var accessibility = true
  var posting = true
  var secure = false
  var supportsInput = true
  var canCreate = true
  var canEnableNewTap = true
  var taps: [TestExpansionEventTap] = []
  lazy var engine: ExpansionEngine = {
    preferences.set(true, forKey: "expansionEnabled")
    return ExpansionEngine(
      preferences: preferences, workspaceCenter: center,
      accessibility: { [unowned self] in accessibility },
      postEventAccess: { [unowned self] in posting },
      secureInput: { [unowned self] in secure },
      supportsInputSource: { [unowned self] in supportsInput },
      makeEventTap: { [unowned self] receive in
        guard canCreate else { return nil }
        let tap = TestExpansionEventTap(receive: receive)
        tap.canEnable = canEnableNewTap
        taps.append(tap)
        return tap
      })
  }()

  func post(_ name: Notification.Name) { center.post(name: name, object: nil) }

  func stop() {
    engine.stop()
    preferences.removePersistentDomain(forName: suite)
  }
}

@MainActor private final class TestExpansionEventTap: ExpansionEventTap {
  var isValid = true
  var isEnabled = true
  var canEnable = true
  var enables = 0
  var invalidations = 0
  let receive: @MainActor (CGEventType, CGEvent) -> Void

  init(receive: @escaping @MainActor (CGEventType, CGEvent) -> Void) { self.receive = receive }

  func enable() {
    enables += 1
    isEnabled = isValid && canEnable
  }

  func invalidate() {
    invalidations += 1
    isValid = false
    isEnabled = false
  }
}
