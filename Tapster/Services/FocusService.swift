import AppKit
import ApplicationServices
import Carbon

@MainActor final class FocusService: ExpansionFocus {
  private var focusedElement: AXUIElement?
  private var token = UUID().uuidString

  func currentTarget() -> ExpansionTarget? {
    guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
    let app = AXUIElementCreateApplication(application.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.015)
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value)
        == .success,
      let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    let element = value as! AXUIElement
    AXUIElementSetMessagingTimeout(element, 0.015)
    if application.bundleIdentifier == Bundle.main.bundleIdentifier {
      var identifier: CFTypeRef?
      AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
      guard identifier as? String == "tapster-expansion-test" else { return nil }
    }
    var subrole: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    if subrole as? String == "AXSecureTextField" { return nil }
    if focusedElement == nil || !CFEqual(focusedElement!, element) {
      focusedElement = element
      token = UUID().uuidString
    }
    return ExpansionTarget(processID: application.processIdentifier, focusID: token)
  }

  /// Only inspect the adjacent character and selection, never the document value.
  func startsAtBoundary() -> Bool {
    guard let element = focusedElement, let range = selectionRange(), range.length == 0 else {
      return false
    }
    if range.location == 0 { return true }
    var previousRange = CFRange(location: range.location - 1, length: 1)
    guard let parameter = AXValueCreate(.cfRange, &previousRange) else { return false }
    var previous: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &previous)
        == .success,
      let text = previous as? String, let character = text.last
    else { return false }
    return !character.isLetter && !character.isNumber && character != "_"
  }

  func selectionRange() -> CFRange? {
    guard let element = focusedElement else { return nil }
    var rawRange: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rawRange)
        == .success,
      let rawRange, CFGetTypeID(rawRange) == AXValueGetTypeID()
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range) else { return nil }
    return range
  }

  static var secureInputEnabled: Bool { IsSecureEventInputEnabled() }

  static var supportsCurrentInputSource: Bool {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
    else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(property).takeUnretainedValue())
  }
}
