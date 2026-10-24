import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @Bindable var state: AppState
  var updater: UpdaterService
  @AppStorage("debounceMilliseconds") private var delay = 250
  @State private var delayText = "250"
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var settingsError: String?
  @FocusState private var delayFocused: Bool

  var body: some View {
    TabView {
      Form {
        Section {
          Toggle(
            "Enable text expansion",
            isOn: Binding(
              get: { state.engine.isEnabled },
              set: {
                state.engine.setEnabled($0, requestPermission: true)
              }))
          HStack {
            Text("Ambiguous keyword delay")
            Spacer()
            HStack(spacing: 6) {
              TextField("Milliseconds", text: $delayText)
                .labelsHidden().accessibilityLabel("Ambiguous keyword delay in milliseconds")
                .focused($delayFocused)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64).multilineTextAlignment(.trailing)
                .onSubmit(commitDelay)
                .onDisappear(perform: commitDelay)
              Text("ms").foregroundStyle(.secondary)
              Stepper("Ambiguous keyword delay", value: $delay, in: 100...1000, step: 50)
                .labelsHidden().fixedSize()
            }
            .accessibilityElement(children: .contain)
          }
        } header: {
          Text("Expansion")
        } footer: {
          Text(
            "When keywords overlap, Textend waits briefly for more typing. Other keywords expand immediately. Range: 100–1,000 ms."
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Section {
          ExpansionTestField().frame(height: 72)
        } header: {
          Text("Try Expansion")
        } footer: {
          Text("Try a saved keyword here. Clipboard placeholders use your current clipboard.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section {
          Toggle(
            "Launch Textend at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
        } header: {
          Text("Startup")
        } footer: {
          Text("Closing the library keeps Textend in the menu bar. Quit Textend to stop expansion.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .tabItem { Label("General", systemImage: "gearshape") }

      Form {
        Section {
          LabeledContent(
            "Accessibility",
            value: state.engine.accessibilityGranted ? "Allowed" : "Required for expansion")
          Button("Open Accessibility…", action: state.engine.openAccessibilitySettings)
          LabeledContent("Status", value: state.engine.status.rawValue)
          if let message = state.engine.lastMessage {
            Text(message).font(.caption).foregroundStyle(.secondary)
          }
        } header: {
          Text("Permissions")
        } footer: {
          Text("Accessibility lets Textend detect keywords and insert snippets in other apps.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section {
          Text(
            "Typing context stays in memory and is cleared when focus changes. Textend does not store typing history. Protected input is never expanded."
          )
          .font(.callout).foregroundStyle(.secondary)
        } header: {
          Text("Privacy")
        }
      }
      .tabItem { Label("Permissions", systemImage: "hand.raised") }

      Form {
        Section {
          if state.engine.excludedBundleIDs.isEmpty {
            Text("Expansion is available in supported applications.").foregroundStyle(.secondary)
          }
          ForEach(state.engine.excludedBundleIDs, id: \.self) { id in
            HStack {
              Text(applicationName(id)).lineLimit(1)
              Spacer()
              Button {
                state.engine.excludedBundleIDs.removeAll { $0 == id }
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.borderless).accessibilityLabel("Remove \(id) from excluded apps")
            }
          }
          Button("Add Application…", action: addExcludedApp)
        } header: {
          Text("Excluded Applications")
        } footer: {
          Text("Textend's editor is always excluded.").font(.caption).foregroundStyle(.secondary)
        }
      }
      .tabItem { Label("Excluded Apps", systemImage: "app.badge") }
      UpdateSettingsView(updater: updater)
        .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
    }
    .formStyle(.grouped)
    .controlSize(.regular)
    .frame(width: 560, height: 520)
    .onAppear {
      delayText = String(delay)
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
    .onChange(of: delay) { _, value in
      delayText = String(value)
      state.engine.updateDelay(value)
    }
    .onChange(of: delayFocused) { _, focused in if !focused { commitDelay() } }
    .alert(
      "Settings",
      isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })
    ) {
      Button("OK", role: .cancel) { settingsError = nil }
    } message: {
      Text(settingsError ?? "")
    }
  }

  private func commitDelay() {
    let value = Int(delayText) ?? delay
    delay = min(1000, max(100, Int((Double(value) / 50).rounded()) * 50))
    delayText = String(delay)
    state.engine.updateDelay(delay)
  }

  private func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = SMAppService.mainApp.status == .enabled
    } catch {
      settingsError = error.localizedDescription
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }

  private func addExcludedApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.begin { response in
      guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else {
        return
      }
      if !state.engine.excludedBundleIDs.contains(id) { state.engine.excludedBundleIDs.append(id) }
    }
  }

  private func applicationName(_ id: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
      return id
    }
    return url.deletingPathExtension().lastPathComponent
  }
}

private struct ExpansionTestField: NSViewRepresentable {
  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    let view = NSTextView()
    view.isRichText = false
    view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    view.textContainerInset = NSSize(width: 8, height: 8)
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.textContainer?.widthTracksTextView = true
    view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.allowsUndo = true
    view.setAccessibilityIdentifier("tapster-expansion-test")
    view.setAccessibilityLabel("Test snippet expansion")
    scroll.documentView = view
    return scroll
  }
  func updateNSView(_ view: NSScrollView, context: Context) {}
}
