import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var state: AppState?

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    let showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    DockVisibility.shared.start(showInDock: showDockIcon)
    let appearance =
      AppAppearance(
        rawValue: UserDefaults.standard.string(forKey: "textendAppearance") ?? "system") ?? .system
    appearance.apply()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let accent =
      AppAccent(rawValue: UserDefaults.standard.string(forKey: "textendAccent") ?? "blue") ?? .blue
    ThemedAppIcon.apply(accent)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if state?.restartApproved == true { return .terminateNow }
    return state?.confirmUnsavedChanges() == false ? .terminateCancel : .terminateNow
  }

  func applicationWillTerminate(_ notification: Notification) {
    state?.engine.stop()
  }
}

@MainActor @Observable final class AppBootstrap {
  var state: AppState?
  var sync: SyncCoordinator?
  var quickAccess: QuickAccessController?
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
        suiteName: BuildIdentity.bundleID + ".sync." + directory.lastPathComponent)!
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
      let appState = AppState(store: library, startPaused: preview)
      state = appState
      quickAccess = QuickAccessController(state: appState)
      appState.openQuickAccess = { [weak self] in self?.quickAccess?.toggle() }
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
      try relaunch()
    } catch {
      do { try sync.rollbackRestart() } catch {
        state.errorMessage =
          "Couldn’t restore the previous sync setting: \(error.localizedDescription)"
        return
      }
      state.errorMessage = error.localizedDescription
    }
  }

  func restart() throws {
    guard let state, state.confirmUnsavedChanges() else { return }
    try relaunch()
  }

  private func relaunch() throws {
    let helper = Process()
    helper.executableURL = URL(fileURLWithPath: "/bin/sh")
    helper.arguments = [
      "-c",
      "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$2\" --args \"$3\"",
      "textend-restart", String(ProcessInfo.processInfo.processIdentifier),
      Bundle.main.bundlePath,
      ProcessInfo.processInfo.arguments.contains("--sync-preview")
        ? "--sync-preview" : "--settings-restarted",
    ]
    helper.standardOutput = FileHandle.nullDevice
    helper.standardError = FileHandle.nullDevice
    try helper.run()
    state?.restartApproved = true
    sync?.stop()
    NSApp.terminate(nil)
  }
}

@main struct TextendApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var bootstrap = AppBootstrap()

  var body: some Scene {
    Window(BuildIdentity.displayName, id: "library") {
      if let state = bootstrap.state {
        LibraryRootView(state: state).textendTheme().onAppear { delegate.state = state }
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
    .commands {
      TextendCommands(
        state: bootstrap.state?.expansionSetup.isPresented == true ? nil : bootstrap.state,
        updater: bootstrap.updater)
    }

    Settings {
      if let state = bootstrap.state {
        SettingsView(
          state: state, updater: bootstrap.updater, sync: bootstrap.sync,
          restart: bootstrap.restart
        ).textendTheme()
      }
    }

    Window("\(BuildIdentity.displayName) Help", id: "help") {
      HelpView().textendTheme()
    }
    .defaultSize(width: 860, height: 600)

    MenuBarExtra(BuildIdentity.displayName, image: "MenuBarIcon") {
      if let state = bootstrap.state {
        MenuBarContent(state: state, updater: bootstrap.updater).textendTheme()
      } else {
        Text("Library unavailable")
        Divider()
        Button("Quit \(BuildIdentity.displayName)") { NSApp.terminate(nil) }.keyboardShortcut("q")
      }
    }
  }
}

private struct LibraryRootView: View {
  var state: AppState

  var body: some View {
    @Bindable var setup = state.expansionSetup
    ContentView(state: state)
      .sheet(isPresented: $setup.isPresented) {
        ExpansionSetupView(setup: setup).textendTheme()
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
    Button("Quick Access") { state.openQuickAccess?() }
    Button("Open \(BuildIdentity.displayName)") {
      openWindow(id: "library")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button(state.engine.isEnabled ? "Pause Expansion" : "Resume Expansion") {
      state.engine.setEnabled(!state.engine.isEnabled, requestPermission: true)
    }
    SettingsLink { Text("Settings…") }
    CheckForUpdatesButton(updater: updater)
    Divider()
    Button("Quit \(BuildIdentity.displayName)", action: state.requestQuit).keyboardShortcut("q")
  }
}

private struct TextendCommands: Commands {
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
      Button("New Composition") { state?.newComposition() }.disabled(state == nil)
      Button("New Collection…") { state?.editCollection(nil) }.keyboardShortcut(
        "n", modifiers: [.command, .shift]
      ).disabled(state == nil)
    }
    CommandGroup(replacing: .saveItem) {
      Button("Save") { state?.save() }.keyboardShortcut("s").disabled(
        state?.isDirty != true || state?.draftError != nil)
      Divider()
      Button("Import Backup…") { state?.importBackup() }.disabled(state == nil)
      Button("Export Backup…") { state?.exportBackup() }.disabled(state == nil)
      Divider()
      Button("Add Example Snippets") { state?.addExamples() }
        .disabled(
          state == nil || state?.store.items.isEmpty != true
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
