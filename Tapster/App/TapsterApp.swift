import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var state: AppState?

  func applicationWillFinishLaunching(_ notification: Notification) {
    let appearance =
      AppAppearance(
        rawValue: UserDefaults.standard.string(forKey: "textendAppearance") ?? "system") ?? .system
    appearance.apply()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if state?.restartApproved == true { return .terminateNow }
    return state?.confirmUnsavedChanges() == false ? .terminateCancel : .terminateNow
  }

  func applicationWillTerminate(_ notification: Notification) { state?.engine.stop() }
}

@MainActor @Observable final class AppBootstrap {
  var state: AppState?
  var sync: SyncCoordinator?
  let updater = UpdaterService()
  var error: String?
  var loading = false
  init() { Task { await load() } }

  func load() async {
    guard !loading else { return }
    loading = true
    defer { loading = false }
    do {
      let directory = try SyncConfiguration.directory()
      let defaults = UserDefaults(
        suiteName: "chat.eastechs.tapster.sync." + directory.lastPathComponent)!
      let coordinator = try SyncCoordinator(
        directory: directory,
        provider: CloudAccountProvider(defaults: defaults), defaults: defaults)
      #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--initialize-cloudkit-schema") {
          try await CloudSchemaInitializer.initialize(
            at: directory.appendingPathComponent("SchemaInitialization.store"))
        }
      #endif
      let library = try await coordinator.openLibrary()
      let preview = ProcessInfo.processInfo.arguments.contains("--sync-preview")
      state = AppState(store: library, startEngine: !preview)
      sync = coordinator
      coordinator.onRestart = { [weak self] next in self?.restart(using: next) }
      updater.state = state
      error = nil
      if coordinator.isActive { NSApp.registerForRemoteNotifications() }
    } catch { self.error = error.localizedDescription }
  }

  private func restart(using next: SyncConfiguration) {
    guard let state, let sync, state.confirmUnsavedChanges() else { return }
    do {
      try sync.commitForRestart(next)
      let helper = Process()
      helper.executableURL = URL(fileURLWithPath: "/bin/sh")
      helper.arguments = [
        "-c",
        "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$2\" --args \"$3\"",
        "textend-restart", String(ProcessInfo.processInfo.processIdentifier),
        Bundle.main.bundlePath,
        ProcessInfo.processInfo.arguments.contains("--sync-preview")
          ? "--sync-preview" : "--sync-restarted",
      ]
      helper.standardOutput = FileHandle.nullDevice
      helper.standardError = FileHandle.nullDevice
      try helper.run()
      state.restartApproved = true
      sync.stop()
      NSApp.terminate(nil)
    } catch {
      do { try sync.rollbackRestart() } catch {
        state.errorMessage =
          "Couldn’t restore the previous sync setting: \(error.localizedDescription)"
        return
      }
      state.errorMessage = error.localizedDescription
    }
  }
}

@main struct TapsterApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var bootstrap = AppBootstrap()

  var body: some Scene {
    WindowGroup("Textend", id: "library") {
      if let state = bootstrap.state {
        ContentView(state: state).textendTheme().onAppear { delegate.state = state }
      } else {
        VStack(spacing: 16) {
          if bootstrap.loading {
            ProgressView("Opening library…")
          } else {
            Label("Couldn’t Open Your Library", systemImage: "exclamationmark.triangle").font(
              .title2)
            Text(bootstrap.error ?? "An unknown storage error occurred.").textSelection(.enabled)
            Button("Try Again") { Task { await bootstrap.load() } }
          }
        }.padding(32).frame(minWidth: 500, minHeight: 300)
      }
    }
    .defaultSize(width: 1320, height: 780)
    .commands { TapsterCommands(state: bootstrap.state, updater: bootstrap.updater) }

    Settings {
      if let state = bootstrap.state {
        SettingsView(state: state, updater: bootstrap.updater, sync: bootstrap.sync).textendTheme()
      }
    }

    Window("Textend Help", id: "help") {
      HelpView().textendTheme()
    }
    .defaultSize(width: 860, height: 600)

    MenuBarExtra("Textend", systemImage: "text.insert") {
      if let state = bootstrap.state {
        MenuBarContent(state: state, updater: bootstrap.updater).textendTheme()
      } else {
        Text("Library unavailable")
      }
    }
  }
}

private struct MenuBarContent: View {
  var state: AppState
  var updater: UpdaterService
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    Text(state.engine.status.rawValue)
    Divider()
    Button("Open Textend") {
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
    CheckForUpdatesButton(updater: updater)
    Divider()
    Button("Quit Textend", action: state.requestQuit).keyboardShortcut("q")
  }
}

private struct TapsterCommands: Commands {
  var state: AppState?
  var updater: UpdaterService
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.helpSearchAction) private var helpSearchAction
  var body: some Commands {
    CommandGroup(replacing: .help) {
      Button("Textend Help") {
        openWindow(id: "help")
        NSApp.activate(ignoringOtherApps: true)
      }
    }
    CommandGroup(after: .appInfo) {
      CheckForUpdatesButton(updater: updater)
    }
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
      Divider()
      Button("Add Example Snippets") { state?.addExamples() }
        .disabled(
          state == nil || state?.store.snippets.isEmpty != true
            || state?.store.collections.isEmpty != true)
    }
    CommandGroup(after: .textEditing) {
      Button(helpSearchAction == nil ? "Find Snippet" : "Search Help") {
        if let helpSearchAction { helpSearchAction() } else { state?.isSearchFocused.toggle() }
      }
      .keyboardShortcut("f").disabled(state == nil && helpSearchAction == nil)
    }
    CommandMenu("Snippet") {
      Button("Duplicate Snippet") { if let snippet = state?.draft { state?.duplicate(snippet) } }
        .keyboardShortcut("d").disabled(state?.draft == nil)
      Button("Copy Expanded Text") { state?.copyExpandedText() }.disabled(
        state?.draft == nil || state?.copyError != nil)
      Button("Delete Snippet") { if let snippet = state?.draft { state?.delete(snippet) } }
        .disabled(state?.draft == nil)
    }
  }
}
