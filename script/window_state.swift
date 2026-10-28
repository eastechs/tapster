#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Read-only diagnostics. --watch samples for 20 seconds without activating the
// app, reporting changes so a UI inspector cannot mask disappearing windows.
func snapshot() -> String {
  let windows =
    CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
  return NSWorkspace.shared.runningApplications
    .filter {
      ["chat.eastechs.tapster", "chat.eastechs.textend.debug"].contains($0.bundleIdentifier ?? "")
    }
    .map { app in
      let visible = windows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
          && ($0[kCGWindowLayer as String] as? Int) == 0
      }.compactMap { $0[kCGWindowNumber as String] as? Int }.sorted()
      return
        "\(app.bundleURL?.path ?? "unknown") pid=\(app.processIdentifier) active=\(app.isActive) hidden=\(app.isHidden) policy=\(app.activationPolicy.rawValue) windows=\(visible) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")"
    }.sorted().joined(separator: "\n")
}
let watching = CommandLine.arguments.contains("--watch")
let end = Date().addingTimeInterval(watching ? 20 : 0)
var previous: String?
repeat {
  let current = snapshot()
  if current != previous {
    print("\(Date().timeIntervalSince1970): \(current)")
    fflush(stdout)
    previous = current
  }
  if watching { Thread.sleep(forTimeInterval: 0.005) }
} while Date() < end
