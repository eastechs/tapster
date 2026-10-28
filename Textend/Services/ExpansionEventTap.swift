import CoreGraphics
import Foundation

@MainActor protocol ExpansionEventTap: AnyObject {
  var isValid: Bool { get }
  var isEnabled: Bool { get }
  func enable()
  func invalidate()
}

@MainActor final class SystemExpansionEventTap: ExpansionEventTap {
  private var port: CFMachPort?
  private var source: CFRunLoopSource?
  private let receive: @MainActor (CGEventType, CGEvent) -> Void

  init?(receive: @escaping @MainActor (CGEventType, CGEvent) -> Void) {
    self.receive = receive
    let types: [CGEventType] = [
      .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
    ]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .defaultTap, eventsOfInterest: mask,
        callback: { _, type, event, info in
          guard let info else { return Unmanaged.passUnretained(event) }
          let tap = Unmanaged<SystemExpansionEventTap>.fromOpaque(info).takeUnretainedValue()
          MainActor.assumeIsolated { tap.receive(type, event) }
          return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return nil }
    self.port = port
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
      CFMachPortInvalidate(port)
      return nil
    }
    self.source = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
  }

  deinit {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let port { CFMachPortInvalidate(port) }
  }

  var isValid: Bool {
    guard let port, let source else { return false }
    return CFMachPortIsValid(port) && CFRunLoopSourceIsValid(source)
  }

  var isEnabled: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

  func enable() {
    if let port, isValid { CGEvent.tapEnable(tap: port, enable: true) }
  }

  func invalidate() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let port { CFMachPortInvalidate(port) }
    source = nil
    port = nil
  }
}
