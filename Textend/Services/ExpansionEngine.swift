import AppKit
import ApplicationServices
import Observation

@MainActor @Observable final class ExpansionEngine {
  enum Status: String {
    case paused = "Paused"
    case permission = "Permission required"
    case secure = "Secure input unavailable"
    case composition = "Input method unavailable"
    case unavailable = "Reconnecting expansion"
    case active = "Expansion active"
  }

  private(set) var status: Status = .paused
  private(set) var lastMessage: String?
  private(set) var isEnabled: Bool
  private(set) var accessibilityGranted = false
  var excludedBundleIDs: [String] {
    didSet {
      preferences.set(excludedBundleIDs, forKey: "excludedBundleIDs")
      cancel()
    }
  }
  private(set) var library = ExpansionLibrary()
  private var indexedBundleID: String?
  private(set) var paletteIsOpen = false
  private var tracking = ExpansionTracking()
  private let focus = FocusService()
  @ObservationIgnored private lazy var insertion = TextInsertionService(
    focus: focus, cursorFailure: { [weak self] message in self?.lastMessage = message })
  private var eventTap: (any ExpansionEventTap)?
  private var timer: Timer?
  private var healthTimer: Timer?
  private var workspaceObservers: [NSObjectProtocol] = []
  private let preferences: UserDefaults
  private let workspaceCenter: NotificationCenter
  private let accessibility: @MainActor () -> Bool
  private let postEventAccess: @MainActor () -> Bool
  private let secureInput: @MainActor () -> Bool
  private let supportsInputSource: @MainActor () -> Bool
  private let makeEventTap:
    @MainActor (@escaping @MainActor (CGEventType, CGEvent) -> Void) -> (any ExpansionEventTap)?
  private var isStarted = false
  private var isSleeping = false
  private var isSessionActive = true

  init(
    preferences: UserDefaults = .standard,
    workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
    accessibility: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
    postEventAccess: @escaping @MainActor () -> Bool = { CGPreflightPostEventAccess() },
    secureInput: @escaping @MainActor () -> Bool = { FocusService.secureInputEnabled },
    supportsInputSource: @escaping @MainActor () -> Bool = {
      FocusService.supportsCurrentInputSource
    },
    makeEventTap:
      @escaping @MainActor (@escaping @MainActor (CGEventType, CGEvent) -> Void) -> (
        any ExpansionEventTap
      )? = { SystemExpansionEventTap(receive: $0) }
  ) {
    self.preferences = preferences
    self.workspaceCenter = workspaceCenter
    self.accessibility = accessibility
    self.postEventAccess = postEventAccess
    self.secureInput = secureInput
    self.supportsInputSource = supportsInputSource
    self.makeEventTap = makeEventTap
    isEnabled = preferences.bool(forKey: "expansionEnabled")
    excludedBundleIDs = preferences.stringArray(forKey: "excludedBundleIDs") ?? []
    updateDelay(preferences.object(forKey: "debounceMilliseconds") as? Int ?? 250)
  }

  func start(initiallyPaused: Bool = false) {
    guard !isStarted else { return }
    // Preview launches pause this session without changing the saved preference.
    // Keep the lifecycle running so Resume can install monitoring normally.
    if initiallyPaused { isEnabled = false }
    isStarted = true
    for name in [
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidResignActiveNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      workspaceObservers.append(
        workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.workspaceChanged(name)
          }
        })
    }
    let healthTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    self.healthTimer = healthTimer
    RunLoop.main.add(healthTimer, forMode: .common)
    refresh()
  }

  private func workspaceChanged(_ name: Notification.Name) {
    guard isStarted else { return }
    rebuildIndex()
    switch name {
    case NSWorkspace.willSleepNotification:
      isSleeping = true
    case NSWorkspace.didWakeNotification:
      isSleeping = false
    case NSWorkspace.sessionDidResignActiveNotification:
      isSessionActive = false
    case NSWorkspace.sessionDidBecomeActiveNotification:
      isSessionActive = true
    default: break
    }
    if name != NSWorkspace.didActivateApplicationNotification {
      // A tap can survive a wake/session transition but stop delivering events.
      // Recreate it even if Core Graphics still reports it as enabled.
      removeTap()
      insertion.finish()
    }
    refresh()
  }

  func updateSnippets(_ snippets: [SnippetRecord]) {
    updateLibrary(ExpansionLibrary(items: snippets))
  }

  func updateLibrary(_ library: ExpansionLibrary) {
    self.library = library
    rebuildIndex()
  }

  private func rebuildIndex() {
    cancel()
    indexedBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    tracking.matcher.update(library.automaticItems(in: indexedBundleID))
  }

  func setPaletteOpen(_ value: Bool) {
    cancel()
    paletteIsOpen = value
  }

  func captureInsertionTarget() -> FocusService.Snapshot? {
    guard accessibility(), postEventAccess(), !secureInput(), !insertion.isBusy,
      let app = NSWorkspace.shared.frontmostApplication,
      !excludedBundleIDs.contains(app.bundleIdentifier ?? "")
    else { return nil }
    return focus.capture()
  }

  func insertManually(_ expansion: ResolvedExpansion, itemID: UUID, target: FocusService.Snapshot)
    throws
  {
    guard accessibility(), postEventAccess(), !secureInput(), supportsInputSource(),
      !excludedBundleIDs.contains(target.bundleID ?? ""),
      let item = library.items.first(where: { $0.id == itemID }),
      library.allows(item, in: target.bundleID),
      focus.matches(target, selection: true)
    else {
      throw TemplateError.invalid(
        "Insertion cancelled. Return to the original field and open Quick Access again.")
    }
    try library.validateContent(item)
    try insertion.insert(expansion, target: target.target, selection: target.selection) {
      [weak self] in
      self?.focus.matches(target, selection: false) == true
    }
  }
  func updateDelay(_ milliseconds: Int) {
    cancel()
    tracking.matcher.delay = Double(min(1000, max(100, milliseconds))) / 1000
  }

  func setEnabled(_ enabled: Bool, requestPermission: Bool = false) {
    isEnabled = enabled
    preferences.set(enabled, forKey: "expansionEnabled")
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
    isStarted = false
    cancel()
    healthTimer?.invalidate()
    healthTimer = nil
    for observer in workspaceObservers {
      workspaceCenter.removeObserver(observer)
    }
    workspaceObservers = []
    removeTap()
    insertion.finish()
    isSleeping = false
    isSessionActive = true
    status = .paused
  }

  func refresh() {
    guard isStarted else { return }
    accessibilityGranted = accessibility()
    var newStatus: Status
    if !isEnabled || isSleeping || !isSessionActive {
      newStatus = .paused
    } else if !accessibilityGranted || !postEventAccess() {
      newStatus = .permission
    } else if secureInput() {
      newStatus = .secure
    } else if !supportsInputSource() {
      newStatus = .composition
    } else {
      newStatus = .active
    }
    if newStatus == .active, !ensureTap() { newStatus = .unavailable }
    if newStatus != status {
      cancel()
      status = newStatus
      ExpansionDiagnostics.record("Engine status: \(newStatus.rawValue)", processID: 0)
    }
    guard status == .active else {
      removeTap()
      return
    }
    if let target = tracking.target, focus.currentTarget() != target { cancel() }
  }

  private func ensureTap() -> Bool {
    if let eventTap {
      if eventTap.isValid && eventTap.isEnabled { return true }
      cancel()
      if eventTap.isValid {
        eventTap.enable()
        if eventTap.isValid && eventTap.isEnabled { return true }
      }
      removeTap()
    }
    guard
      let tap = makeEventTap({ [weak self] type, event in
        self?.receive(type: type, event: event)
      })
    else { return false }
    eventTap = tap
    tap.enable()
    guard tap.isValid && tap.isEnabled else {
      removeTap()
      return false
    }
    ExpansionDiagnostics.record("Keyboard listener installed", processID: 0)
    return true
  }

  private func removeTap() {
    eventTap?.invalidate()
    eventTap = nil
  }

  private func receive(type: CGEventType, event: CGEvent) {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      cancel()
      eventTap?.enable()
      return
    }
    if event.getIntegerValueField(.eventSourceUserData) == TextInsertionService.eventMarker {
      return
    }
    if type != .flagsChanged { insertion.cancelCursorPlacement() }
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
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    guard !paletteIsOpen, status == .active, !insertion.isBusy, !secureInput(),
      !event.flags.contains(.maskCommand), !event.flags.contains(.maskControl),
      !event.flags.contains(.maskAlternate),
      event.getIntegerValueField(.keyboardEventAutorepeat) == 0 || code == 51,
      let app = NSWorkspace.shared.frontmostApplication,
      !excludedBundleIDs.contains(app.bundleIdentifier ?? ""),
      let current = focus.currentTarget()
    else {
      cancel()
      return
    }
    if indexedBundleID != app.bundleIdentifier { rebuildIndex() }
    if code == 51 {
      timer?.invalidate()
      timer = nil
      tracking.backspace(target: current, selection: focus.selectionRange())
      return
    }
    guard ![36, 48, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(code) else {
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
    guard !paletteIsOpen, status == .active, !secureInput(),
      accessibility(), postEventAccess(), focus.currentTarget() == target,
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
      let result = try library.resolve(
        snippet, clipboard: library.needsClipboard(snippet) ? insertion.readText() : nil)
      guard focus.currentTarget() == target,
        library.allows(snippet, in: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
      else { return }
      try insertion.replace(
        keyword: snippet.keyword, with: result.text, target: target,
        cursorUTF16Offset: result.cursorUTF16Offset)
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
