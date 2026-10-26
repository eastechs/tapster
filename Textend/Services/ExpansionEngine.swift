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
  private var tracking = ExpansionTracking()
  private let focus = FocusService()
  @ObservationIgnored private lazy var insertion = TextInsertionService(
    focus: focus, cursorFailure: { [weak self] message in self?.lastMessage = message })
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var timer: Timer?
  private var healthTimer: Timer?
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
    tracking.matcher.update(snippets)
  }
  func updateDelay(_ milliseconds: Int) {
    cancel()
    tracking.matcher.delay = Double(min(1000, max(100, milliseconds))) / 1000
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
      ExpansionDiagnostics.record("Engine status: \(newStatus.rawValue)", processID: 0)
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
    if let target = tracking.target, focus.currentTarget() != target { cancel() }
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
      let current = focus.currentTarget()
    else {
      cancel()
      return
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    guard ![36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(code) else {
      cancel()
      return
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
    let selection = focus.selectionRange()
    let starting = tracking.target != current
    let boundary = starting ? focus.startsAtBoundary() : nil
    if starting {
      ExpansionDiagnostics.record(
        boundary == false ? "Typing run begins inside a word" : "Typing run begins at a boundary",
        processID: current.processID)
    }
    timer?.invalidate()
    guard
      let match = tracking.input(
        text, target: current, selection: selection,
        startsAtBoundary: boundary, now: ProcessInfo.processInfo.systemUptime)
    else { return }
    ExpansionDiagnostics.record("Keyword matched", processID: current.processID)
    if let deadline = match.deadline {
      timer = Timer.scheduledTimer(
        withTimeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime), repeats: false
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.expand(match, target: current)
        }
      }
    } else {
      // Return the physical event first so it reaches the host before our backspaces.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
        self?.expand(match, target: current)
      }
    }
  }

  private func expand(_ match: TriggerMatch, target: ExpansionTarget, attempt: Int = 0) {
    guard status == .active, !FocusService.secureInputEnabled,
      AXIsProcessTrusted(), CGPreflightPostEventAccess(), focus.currentTarget() == target,
      match.generation == tracking.matcher.generation
    else { return }
    let selection = focus.selectionRange()
    var matchingKeyword: Bool?
    if let selection {
      let length = match.snippet.keyword.utf16.count
      if selection.location >= length {
        matchingKeyword = focus.text(
          in: CFRange(location: selection.location - length, length: length)
        )
        .map { $0 == match.snippet.keyword }
      }
    }
    // Accessibility can trail delivery of the physical final key to another process.
    switch tracking.readiness(selection: selection, matchingKeyword: matchingKeyword) {
    case .cancelled:
      cancel()
      return
    case .waiting:
      if attempt < 14 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
          self?.expand(match, target: target, attempt: attempt + 1)
        }
      } else {
        ExpansionDiagnostics.record(
          "AX keyword confirmation timed out", processID: target.processID)
        cancel()
      }
      return
    case .ready: break
    }
    guard let snippet = tracking.matcher.take(match, now: ProcessInfo.processInfo.systemUptime)
    else {
      return
    }
    defer { tracking.reset() }
    do {
      try ExpansionTransaction.perform(
        snippet, target: target, clipboard: insertion, focus: focus, insertion: insertion)
      ExpansionDiagnostics.record("Expansion events posted", processID: target.processID)
      lastMessage = nil
    } catch { lastMessage = error.localizedDescription }
  }

  private func cancel() {
    insertion.cancelCursorPlacement()
    timer?.invalidate()
    timer = nil
    tracking.reset()
  }
}
