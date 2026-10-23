import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var state: AppState?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    state?.confirmUnsavedChanges() == false ? .terminateCancel : .terminateNow
  }

  func applicationWillTerminate(_ notification: Notification) { state?.engine.stop() }
}

@MainActor @Observable final class AppBootstrap {
  var state: AppState?
  var error: String?
  init() { load() }
  func load() {
    do {
      state = AppState(store: try LibraryStore())
      error = nil
    } catch { self.error = error.localizedDescription }
  }
}

@main struct TapsterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var bootstrap = AppBootstrap()

  var body: some Scene {
    WindowGroup("Tapster", id: "library") {
      if let state = bootstrap.state {
        ContentView(state: state).onAppear { delegate.state = state }
      } else {
        VStack(spacing: 16) {
          Label("Couldn’t Open Your Library", systemImage: "exclamationmark.triangle").font(.title2)
          Text(bootstrap.error ?? "An unknown storage error occurred.").textSelection(.enabled)
          Button("Try Again") { bootstrap.load() }
        }.padding(32).frame(minWidth: 500, minHeight: 300)
      }
    }
    .defaultSize(width: 1320, height: 780)
    .commands { TapsterCommands(state: bootstrap.state) }

    Settings {
      if let state = bootstrap.state { SettingsView(state: state) }
    }

    MenuBarExtra("Tapster", systemImage: "text.insert") {
      if let state = bootstrap.state {
        MenuBarContent(state: state)
      } else {
        Text("Library unavailable")
      }
    }
  }
}

private struct MenuBarContent: View {
  var state: AppState
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Text(state.engine.status.rawValue)
    Divider()
    Button("Open Tapster") {
      if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "tapster-library" }) {
        window.makeKeyAndOrderFront(nil)
      } else {
        openWindow(id: "library")
      }
      NSApp.activate(ignoringOtherApps: true)
    }
    Button(state.engine.isEnabled ? "Pause Expansion" : "Resume Expansion") {
      state.engine.setEnabled(!state.engine.isEnabled, requestPermission: true)
    }
    SettingsLink { Text("Settings…") }
    Divider()
    Button("Quit Tapster", action: state.requestQuit).keyboardShortcut("q")
  }
}

private struct TapsterCommands: Commands {
  var state: AppState?
  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Snippet") { state?.newSnippet() }.keyboardShortcut("n").disabled(state == nil)
      Button("New Collection…") { state?.editCollection(nil) }.keyboardShortcut(
        "n", modifiers: [.command, .shift]
      ).disabled(state == nil)
    }
    CommandGroup(replacing: .saveItem) {
      Button("Save Snippet") { state?.save() }.keyboardShortcut("s").disabled(
        state?.isDirty != true || state?.draftError != nil)
      Divider()
      Button("Import Backup…") { state?.importBackup() }.disabled(state == nil)
      Button("Export Backup…") { state?.exportBackup() }.disabled(state == nil)
    }
    CommandGroup(after: .textEditing) {
      Button("Find Snippet") { state?.isSearchFocused.toggle() }.keyboardShortcut("f").disabled(
        state == nil)
    }
    CommandMenu("Snippet") {
      Button("Duplicate Snippet") { if let snippet = state?.draft { state?.duplicate(snippet) } }
        .keyboardShortcut("d").disabled(state?.draft == nil)
      Button("Copy Expanded Text") { state?.copyExpandedText() }.disabled(
        state?.draft == nil || state?.draftError != nil)
      Button("Delete Snippet") { if let snippet = state?.draft { state?.delete(snippet) } }
        .disabled(state?.draft == nil)
    }
  }
}
