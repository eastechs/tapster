import CloudKit
import Foundation
import Security

@MainActor protocol CloudAccountProviding {
  var isProvisioned: Bool { get }
  func currentAccount() async -> CloudAccount
}

@MainActor final class CloudAccountProvider: CloudAccountProviding {
  private let defaults: UserDefaults
  init(defaults: UserDefaults) { self.defaults = defaults }

  var isProvisioned: Bool {
    guard let task = SecTaskCreateFromSelf(nil),
      let containers = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String],
      let services = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.icloud-services" as CFString, nil) as? [String]
    else { return false }
    return containers.contains(SyncConfiguration.containerIdentifier)
      && services.contains("CloudKit")
  }

  func currentAccount() async -> CloudAccount {
    guard isProvisioned else {
      return .unavailable(
        "This build needs a CloudKit provisioning profile. Local snippets remain available.")
    }
    let identity = FileManager.default.ubiquityIdentityToken.flatMap {
      try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: false)
    }.map { SyncConfiguration.accountKey($0.base64EncodedString()) }
    do {
      let container = CKContainer(identifier: SyncConfiguration.containerIdentifier)
      switch try await container.accountStatus() {
      case .available:
        let id = SyncConfiguration.accountKey(try await container.userRecordID().recordName)
        defaults.set(id, forKey: "accountKey")
        defaults.set(identity, forKey: "identityToken")
        return .available(id)
      case .noAccount, .restricted:
        defaults.removeObject(forKey: "accountKey")
        defaults.removeObject(forKey: "identityToken")
        return .signedOut
      default: return cachedAccount(identity: identity)
      }
    } catch { return cachedAccount(identity: identity) }
  }

  private func cachedAccount(identity: String?) -> CloudAccount {
    // Offline use is permitted only while the system's iCloud identity still matches.
    if let identity, identity == defaults.string(forKey: "identityToken"),
      let account = defaults.string(forKey: "accountKey")
    {
      return .available(account)
    }
    return .unavailable(
      "iCloud is temporarily unavailable. Check your connection, then check the account again.")
  }
}
