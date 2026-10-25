import Combine
import Sparkle
import SwiftUI

@MainActor final class UpdaterService: NSObject, ObservableObject, SPUUpdaterDelegate {
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecks = false
  @Published private(set) var automaticallyDownloads = false
  @Published private(set) var unavailableReason: String?
  weak var state: AppState?
  private var controller: SPUStandardUpdaterController?

  override init() {
    super.init()
    #if DEBUG
      unavailableReason = "Updates are disabled in development builds."
    #else
      guard !ProcessInfo.processInfo.arguments.contains("--sync-preview") else {
        unavailableReason = "Updates are disabled in sync verification previews."
        return
      }
      let info = Bundle.main.infoDictionary ?? [:]
      guard let feed = info["SUFeedURL"] as? String,
        let url = URL(string: feed), url.scheme == "https", url.host != nil,
        let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32
      else {
        unavailableReason = "Updates are not configured for this build."
        return
      }
      let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
      self.controller = controller
      let updater = controller.updater
      updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main)
        .assign(to: &$canCheckForUpdates)
      updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: DispatchQueue.main)
        .assign(to: &$automaticallyChecks)
      updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: DispatchQueue.main)
        .assign(to: &$automaticallyDownloads)
      do {
        try updater.start()
      } catch {
        unavailableReason = error.localizedDescription
      }
    #endif
  }

  func checkForUpdates() { controller?.checkForUpdates(nil) }
  func setAutomaticallyChecks(_ enabled: Bool) {
    controller?.updater.automaticallyChecksForUpdates = enabled
  }
  func setAutomaticallyDownloads(_ enabled: Bool) {
    controller?.updater.automaticallyDownloadsUpdates = enabled
  }

  func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
    state?.confirmUnsavedChanges() ?? true
  }
}

struct CheckForUpdatesButton: View {
  @ObservedObject var updater: UpdaterService
  var body: some View {
    Button("Check for Updates…", action: updater.checkForUpdates)
      .disabled(!updater.canCheckForUpdates)
  }
}

struct UpdateSettingsView: View {
  @ObservedObject var updater: UpdaterService
  var body: some View {
    Form {
      Section {
        Toggle(
          "Automatically check for updates",
          isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticallyChecks))
        Toggle(
          "Automatically download and install updates",
          isOn: Binding(
            get: { updater.automaticallyDownloads }, set: updater.setAutomaticallyDownloads)
        ).disabled(!updater.automaticallyChecks)
        CheckForUpdatesButton(updater: updater)
      } header: {
        Text("Software Updates")
      } footer: {
        Text(updater.unavailableReason ?? "Textend checks for updates daily when enabled.")
          .font(.caption).foregroundStyle(.secondary)
      }
      .disabled(updater.unavailableReason != nil)
    }
  }
}
