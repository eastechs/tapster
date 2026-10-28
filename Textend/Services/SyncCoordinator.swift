import AppKit
import CloudKit
import CoreData
import Foundation
import Observation

@MainActor @Observable final class SyncCoordinator {
  private(set) var configuration: SyncConfiguration
  private(set) var account: CloudAccount = .unavailable("Checking iCloud…")
  private(set) var isActive = false
  private(set) var requiresRestart = false
  private(set) var recoveryFailed = false
  private(set) var activity = "Off"
  private(set) var message: String?
  private(set) var lastTransfer: Date?
  private let directory: URL
  private let provider: any CloudAccountProviding
  private let defaults: UserDefaults
  private let makeStore: @MainActor (URL, String?) throws -> LibraryStore
  private weak var store: LibraryStore?
  private var observers: [NSObjectProtocol] = []
  private var workspaceObservers: [NSObjectProtocol] = []
  private var transfers: Set<UUID> = []
  private var transferError: String?
  private var refreshTask: Task<Void, Never>?
  private var storeIdentifier: String?
  var onRestart: ((SyncConfiguration) -> Void)?

  init(
    directory: URL, provider: any CloudAccountProviding, defaults: UserDefaults,
    makeStore: @escaping @MainActor (URL, String?) throws -> LibraryStore = {
      try LibraryStore(url: $0, cloudContainer: $1)
    }
  ) throws {
    self.directory = directory
    self.provider = provider
    self.defaults = defaults
    self.makeStore = makeStore
    configuration = try SyncConfiguration.load(in: directory)
    lastTransfer = defaults.object(forKey: "lastTransfer." + configuration.libraryName) as? Date
  }

  var accountDescription: String {
    switch account {
    case .available: "Signed in"
    case .signedOut: "Not signed in"
    case .unavailable: "Unavailable"
    }
  }

  var canEnable: Bool {
    if case .available = account { return provider.isProvisioned && !requiresRestart }
    return false
  }

  var changesAccount: Bool {
    guard let owner = configuration.owner, case .available(let id) = account else { return false }
    return id != owner
  }

  func openLibrary() async throws -> LibraryStore {
    account = await provider.currentAccount()
    isActive = configuration.canSync(with: account) && provider.isProvisioned
    let url = try configuration.storeURL(in: directory)
    let recovery = url.appendingPathExtension("recovery.json")
    let hasRecovery = FileManager.default.fileExists(atPath: recovery.path)
    // Recovery is restored locally before any subsequent, explicitly enabled sync.
    let library = try makeStore(
      url,
      isActive && !hasRecovery ? SyncConfiguration.containerIdentifier : nil)
    if hasRecovery {
      if library.items.isEmpty && library.collections.isEmpty {
        try library.importRecovery(Data(contentsOf: recovery))
      }
      isActive = false
      configuration.enabled = false
      try configuration.save(in: directory)
      try FileManager.default.removeItem(at: recovery)
    }
    store = library
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      ofType: NSSQLiteStoreType, at: url, options: nil)
    storeIdentifier = metadata[NSStoreUUIDKey] as? String
    updateAvailability()
    observe()
    return library
  }

  func checkAccount() async {
    let current = await provider.currentAccount()
    account = current
    if isActive {
      switch current {
      case .signedOut: suspendForAccountChange()
      case .available where !configuration.canSync(with: current): suspendForAccountChange()
      case .unavailable: updateAvailability()
      default: updateAvailability()
      }
    } else {
      updateAvailability()
    }
  }

  func requestChange(_ enabled: Bool) {
    guard !recoveryFailed else { return }
    do { onRestart?(try configuration.changingSync(to: enabled, account: account)) } catch {
      message = error.localizedDescription
    }
  }

  func commitForRestart(_ next: SyncConfiguration) throws {
    // The caller has already resolved drafts. Only write after restart has been accepted.
    try next.save(in: directory)
  }

  func rollbackRestart() throws { try configuration.save(in: directory) }

  func stop() {
    refreshTask?.cancel()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    observers = []
    workspaceObservers = []
  }

  private func updateAvailability() {
    guard !requiresRestart else { return }
    switch account {
    case .signedOut:
      activity = "Unavailable"
      message = "Sign in to iCloud in System Settings. Your local library remains available."
    case .unavailable(let reason):
      activity = configuration.enabled ? "Waiting for iCloud" : "Off"
      message = reason
    case .available:
      activity =
        isActive
        ? transferError != nil
          ? "Waiting for iCloud" : transfers.isEmpty ? "Waiting for changes" : "Syncing"
        : "Off"
      message =
        changesAccount
        ? "This is a different iCloud account. Enabling sync opens its separate library. Your previous library stays on this Mac."
        : configuration.enabled && !isActive
          ? "Restart Textend to resume sync with this account."
          : transferError
    }
  }

  private func observe() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if self.isActive { self.suspendForAccountChange() }
          Task { await self.checkAccount() }
        }
      })
    observers.append(
      center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) {
        [weak self] notification in
        MainActor.assumeIsolated {
          guard let self, notification.userInfo?[NSStoreUUIDKey] as? String == self.storeIdentifier
          else { return }
          self.refreshLibrary()
        }
      })
    observers.append(
      center.addObserver(
        forName: NSPersistentCloudKitContainer.eventChangedNotification,
        object: nil, queue: .main
      ) { [weak self] notification in
        MainActor.assumeIsolated {
          guard let self,
            let event = notification.userInfo?[
              NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
              as? NSPersistentCloudKitContainer.Event,
            event.storeIdentifier == self.storeIdentifier, self.isActive
          else { return }
          if event.endDate == nil {
            self.transfers.insert(event.identifier)
            self.activity = "Syncing"
          } else {
            self.transfers.remove(event.identifier)
            if let error = event.error {
              self.transferError = error.localizedDescription
            } else {
              if event.succeeded && event.type != .setup {
                self.lastTransfer = event.endDate
                self.defaults.set(
                  event.endDate, forKey: "lastTransfer." + self.configuration.libraryName)
              }
              self.transferError = nil
            }
            self.updateAvailability()
            if event.type == .import { self.refreshLibrary() }
          }
        }
      })
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.didActivateApplicationNotification] {
      workspaceObservers.append(
        NSWorkspace.shared.notificationCenter.addObserver(
          forName: name,
          object: nil, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.refreshLibrary() }
        })
    }
  }

  private func refreshLibrary() {
    guard !requiresRestart else { return }
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      guard let self else { return }
      if self.isActive { await self.checkAccount() }
      guard !Task.isCancelled, !self.requiresRestart else { return }
      do { try self.store?.reload() } catch { self.message = error.localizedDescription }
    }
  }

  private func suspendForAccountChange() {
    guard !requiresRestart else { return }
    requiresRestart = true
    isActive = false
    activity = "Restart required"
    refreshTask?.cancel()
    do {
      // Capture the last observed library before releasing the account-bound store.
      let recovery = try store?.recoveryData()
      store?.suspend()
      var next = configuration
      next.enabled = false
      next.libraryName = UUID().uuidString
      if let owner = next.owner { next.accountLibraries[owner] = next.libraryName }
      let url = try next.storeURL(in: directory).appendingPathExtension("recovery.json")
      if let recovery {
        try recovery.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      }
      try next.save(in: directory)
      configuration = next
      message =
        "Your iCloud account changed. Restart Textend to use the preserved local library, then explicitly enable sync for the account you want."
    } catch {
      store?.suspend()
      recoveryFailed = true
      message =
        "Your iCloud account changed. Export a backup before quitting: \(error.localizedDescription)"
    }
  }
}
