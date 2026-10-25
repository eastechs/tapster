import AppKit
import ApplicationServices
import Observation

@MainActor @Observable final class ExpansionEngine {
  enum Status: String {
    case paused = "Paused"
    case permission = "Permission required"
    case secure = "Secure input unavailable"
    case composition = "Input method unavailable"
    case active = "Expansion active"
  }

  private(set) var status: Status = .paused
  private(set) var lastMessage: String?
  private(set) var isEnabled: Bool
  private(set) var accessibilityGranted = false
  var excludedBundleIDs: [String] {
    didSet {
      UserDefaults.standard.set(excludedBundleIDs, forKey: "excludedBundleIDs")
      cancel()
    }
  }
  private var matcher = TriggerMatcher()
  private let focus = FocusService()
  @ObservationIgnored private lazy var insertion = TextInsertionService(
    focus: focus, cursorFailure: { [weak self] message in self?.lastMessage = message })
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var timer: Timer?
  private var healthTimer: Timer?
  private var target: ExpansionTarget?
  private var expectedCaret: Int?
  private var workspaceObservers: [NSObjectProtocol] = []

  init() {
    isEnabled = UserDefaults.standard.bool(forKey: "expansionEnabled")
    excludedBundleIDs = UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? []
    updateDelay(UserDefaults.standard.object(forKey: "debounceMilliseconds") as? Int ?? 250)
  }

  func start() {
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
      NSWorkspace.didWakeNotification,
    ] {
      workspaceObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.cancel()
            self?.refresh()
          }
        })
    }
    healthTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    refresh()
  }

  func updateSnippets(_ snippets: [SnippetRecord]) {
    cancel()
    matcher.update(snippets)
  }
  func updateDelay(_ milliseconds: Int) {
    cancel()
    matcher.delay = Double(min(1000, max(100, milliseconds))) / 1000
  }

  func setEnabled(_ enabled: Bool, requestPermission: Bool = false) {
    isEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: "expansionEnabled")
    cancel()
    if enabled && requestPermission { requestAccessibility() }
    refresh()
  }

  func requestAccessibility() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    refresh()
  }

  func openAccessibilitySettings() {
    requestAccessibility()
    // Repeated permission requests may not show a prompt. Always provide a route to Settings.
    let settingsURL = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    if !NSWorkspace.shared.open(settingsURL) {
      lastMessage =
        "Open System Settings → Privacy & Security → Accessibility, then enable Textend."
    }
  }

  func stop() {
    cancel()
    healthTimer?.invalidate()
    healthTimer = nil
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    workspaceObservers = []
    removeTap()
    insertion.finish()
  }

  private func refresh() {
    accessibilityGranted = AXIsProcessTrusted()
    let newStatus: Status
    if !isEnabled {
      newStatus = .paused
    } else if !accessibilityGranted || !CGPreflightPostEventAccess() {
      newStatus = .permission
    } else if FocusService.secureInputEnabled {
      newStatus = .secure
    } else if !FocusService.supportsCurrentInputSource {
      newStatus = .composition
    } else {
      newStatus = .active
    }
    if newStatus != status {
      cancel()
      status = newStatus
    }
    guard status == .active else {
      removeTap()
      return
    }
    if let eventTap {
      if !CGEvent.tapIsEnabled(tap: eventTap) {
        cancel()
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
    } else {
      installTap()
    }
    if let target, focus.currentTarget() != target { cancel() }
  }

  private func installTap() {
    let types: [CGEventType] = [
      .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
    ]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    let info = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap,
        options: .defaultTap, eventsOfInterest: mask,
        callback: { _, type, event, info in
          guard let info else { return Unmanaged.passUnretained(event) }
          let engine = Unmanaged<ExpansionEngine>.fromOpaque(info).takeUnretainedValue()
          MainActor.assumeIsolated { engine.receive(type: type, event: event) }
          return Unmanaged.passUnretained(event)
        }, userInfo: info)
    else {
      status = .permission
      lastMessage =
        "macOS could not monitor typing. Check Textend's Accessibility permission, then restart Textend."
      return
    }
    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func removeTap() {
    if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    if let eventTap { CFMachPortInvalidate(eventTap) }
    runLoopSource = nil
    eventTap = nil
  }

  private func receive(type: CGEventType, event: CGEvent) {
    if event.getIntegerValueField(.eventSourceUserData) == TextInsertionService.eventMarker {
      return
    }
    if type != .flagsChanged { insertion.cancelCursorPlacement() }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      cancel()
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      return
    }
    if type == .flagsChanged {
      if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        || event.getIntegerValueField(.keyboardEventKeycode) == 57
      {
        cancel()
      }
      return
    }
    guard type == .keyDown else {
      cancel()
      return
    }
    guard status == .active, !insertion.isBusy, !FocusService.secureInputEnabled,
      !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl),
      !event.flags.contains(.maskAlternate),
      event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
      let app = NSWorkspace.shared.frontmostApplication,
      !excludedBundleIDs.contains(app.bundleIdentifier ?? ""),
      let current = focus.currentTarget(),
      let selection = focus.selectionRange(), selection.length == 0
    else {
      cancel()
      return
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    guard ![36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(code) else {
      cancel()
      return
    }
    if target != current || expectedCaret.map({ $0 != selection.location }) == true {
      cancel()
      target = current
      matcher.reset(atBoundary: focus.startsAtBoundary())
    }
    var characters = [UniChar](repeating: 0, count: 16)
    var length = 0
    event.keyboardGetUnicodeString(
      maxStringLength: 16, actualStringLength: &length, unicodeString: &characters)
    guard length > 0 else {
      cancel()
      return
    }
    let text = String(utf16CodeUnits: characters, count: length)
    expectedCaret = selection.location + length
    timer?.invalidate()
    guard let match = matcher.input(text, now: ProcessInfo.processInfo.systemUptime) else { return }
    if let deadline = match.deadline {
      timer = Timer.scheduledTimer(
        withTimeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime), repeats: false
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.expand(match, target: current, caret: selection.location + length)
        }
      }
    } else {
      // Return the physical event first so it reaches the host before our backspaces.
      DispatchQueue.main.async { [weak self] in
        self?.expand(match, target: current, caret: selection.location + length)
      }
    }
  }

  private func expand(_ match: TriggerMatch, target: ExpansionTarget, caret: Int, attempt: Int = 0)
  {
    guard status == .active, !FocusService.secureInputEnabled,
      AXIsProcessTrusted(), CGPreflightPostEventAccess(), focus.currentTarget() == target,
      match.generation == matcher.generation,
      let selection = focus.selectionRange(), selection.length == 0
    else { return }
    // Accessibility can trail delivery of the physical final key to another process.
    if selection.location != caret {
      if selection.location < caret && attempt < 5 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
          self?.expand(match, target: target, caret: caret, attempt: attempt + 1)
        }
      }
      return
    }
    guard let snippet = matcher.take(match, now: ProcessInfo.processInfo.systemUptime) else {
      return
    }
    do {
      try ExpansionTransaction.perform(
        snippet, target: target, clipboard: insertion, focus: focus, insertion: insertion)
      lastMessage = nil
    } catch { lastMessage = error.localizedDescription }
  }

  private func cancel() {
    insertion.cancelCursorPlacement()
    timer?.invalidate()
    timer = nil
    matcher.reset()
    target = nil
    expectedCaret = nil
  }
}
