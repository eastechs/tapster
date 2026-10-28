import Foundation

/// Keyboard events establish the typed run. Accessibility is optional corroboration;
/// web editors may omit numeric ranges or update them after several keystrokes.
struct ExpansionTracking {
  enum Readiness { case ready, waiting, cancelled }

  var matcher = TriggerMatcher()
  private(set) var target: ExpansionTarget?

  mutating func input(
    _ text: String, target: ExpansionTarget, selection: CFRange?,
    startsAtBoundary: @autoclosure () -> Bool?, now: TimeInterval
  ) -> TriggerMatch? {
    if let selection, selection.length != 0 {
      reset()
      return nil
    }
    if self.target != target {
      reset()
      self.target = target
      // With no readable context, a fresh physical typing run is our boundary.
      // Once typing starts, the matcher still rejects keywords embedded in words.
      matcher.reset(atBoundary: startsAtBoundary() ?? true)
    }
    return matcher.input(text, now: now)
  }

  mutating func backspace(target: ExpansionTarget, selection: CFRange?) {
    guard self.target == target, selection.map({ $0.length == 0 }) ?? true else {
      reset()
      return
    }
    matcher.backspace()
  }

  func readiness(selection: CFRange?, matchingKeyword: Bool? = nil) -> Readiness {
    guard let selection else { return .ready }
    guard selection.length == 0 else { return .cancelled }
    // Numeric ranges alone can be stale or relative to a different web node.
    // Only readable text can corroborate the typing run; missing AX data is optional.
    if let matchingKeyword { return matchingKeyword ? .ready : .waiting }
    return .ready
  }

  mutating func reset() {
    matcher.reset()
    target = nil
  }
}
