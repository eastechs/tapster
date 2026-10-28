import ApplicationServices
import XCTest

@testable import TextendCore

final class FocusTests: XCTestCase {
  @MainActor func testAppWithoutAXFocusStillHasStableTarget() throws {
    let h = FocusHarness()
    let target = try XCTUnwrap(h.service.currentTarget())
    XCTAssertEqual(target.processID, h.application?.processID)
    XCTAssertEqual(h.service.currentTarget(), target)
    XCTAssertNil(h.service.selectionRange())
    XCTAssertNil(h.service.startsAtBoundary())
  }

  @MainActor func testWebElementRecreationAndAXAvailabilityDoNotCancelTyping() throws {
    let h = FocusHarness()
    let target = try XCTUnwrap(h.service.currentTarget())
    h.element = AXUIElementCreateApplication(900_001)
    h.window = AXUIElementCreateApplication(900_002)
    XCTAssertEqual(h.service.currentTarget(), target)
    h.element = AXUIElementCreateApplication(900_003)
    XCTAssertEqual(h.service.currentTarget(), target)
    h.element = nil
    h.window = nil
    XCTAssertEqual(h.service.currentTarget(), target)
    h.window = AXUIElementCreateApplication(900_002)
    XCTAssertEqual(h.service.currentTarget(), target)
  }

  @MainActor func testAppAndWindowChangesInvalidateTarget() throws {
    let h = FocusHarness()
    h.window = AXUIElementCreateApplication(900_002)
    let first = try XCTUnwrap(h.service.currentTarget())
    h.window = AXUIElementCreateApplication(900_004)
    let second = try XCTUnwrap(h.service.currentTarget())
    XCTAssertNotEqual(second, first)
    h.application = FocusService.Application(processID: 900_005, bundleID: "another.app")
    let third = try XCTUnwrap(h.service.currentTarget())
    XCTAssertNotEqual(third, second)
    h.application = nil
    XCTAssertNil(h.service.currentTarget())
    h.application = FocusService.Application(processID: 900_005, bundleID: "another.app")
    XCTAssertNotEqual(h.service.currentTarget(), third)
  }

  @MainActor func testManualSnapshotRequiresExactEditableElementAndSelection() throws {
    let h = FocusHarness()
    h.element = AXUIElementCreateApplication(900_001)
    h.role = kAXTextAreaRole
    h.range = CFRange(location: 4, length: 8)
    let snapshot = try XCTUnwrap(h.service.capture())
    XCTAssertTrue(h.service.matches(snapshot, selection: true))
    h.range = CFRange(location: 5, length: 8)
    XCTAssertFalse(h.service.matches(snapshot, selection: true))
    XCTAssertTrue(h.service.matches(snapshot, selection: false))
    h.element = AXUIElementCreateApplication(900_003)
    XCTAssertFalse(h.service.matches(snapshot, selection: false))
    h.enabled = false
    XCTAssertNil(h.service.capture())
    h.enabled = true
    h.role = kAXButtonRole
    XCTAssertNil(h.service.capture())
    h.role = kAXTextAreaRole
    h.range = nil
    XCTAssertNil(h.service.capture())
  }

  @MainActor func testSecureFieldsAndOwnEditorsRemainExcluded() {
    let h = FocusHarness()
    h.element = AXUIElementCreateApplication(900_001)
    h.subrole = "AXSecureTextField"
    XCTAssertNil(h.service.currentTarget())
    h.subrole = nil
    XCTAssertNotNil(h.service.currentTarget())
    for id in BuildIdentity.applicationBundleIDs.union(["textend.test"]) {
      h.application?.bundleID = id
      XCTAssertNil(h.service.currentTarget(), "Both Textend editors must stay excluded")
    }
    h.identifier = "textend-expansion-test"
    XCTAssertNotNil(h.service.currentTarget())
    h.element = nil
    XCTAssertNil(h.service.currentTarget())
  }
}

@MainActor private final class FocusHarness {
  var application: FocusService.Application? = .init(processID: 900_000, bundleID: "web.app")
  var element: AXUIElement?
  var window: AXUIElement?
  var subrole: String?
  var identifier: String?
  var role: String?
  var range: CFRange?
  var enabled = true
  lazy var service = FocusService(
    application: { [unowned self] in application },
    attribute: { [unowned self] _, name in
      switch name {
      case kAXFocusedUIElementAttribute: return element
      case kAXFocusedWindowAttribute: return window
      case kAXSubroleAttribute: return subrole as CFString?
      case kAXIdentifierAttribute: return identifier as CFString?
      case kAXRoleAttribute: return role as CFString?
      case kAXEnabledAttribute: return enabled ? kCFBooleanTrue : kCFBooleanFalse
      case kAXSelectedTextRangeAttribute:
        guard var range else { return nil }
        return AXValueCreate(.cfRange, &range)
      default: return nil
      }
    }, ownBundleID: "textend.test")
}
