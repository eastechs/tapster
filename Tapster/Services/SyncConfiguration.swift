import CryptoKit
import Foundation

enum CloudAccount: Equatable {
  case available(String)
  case signedOut
  case unavailable(String)
}

struct SyncConfiguration: Codable, Equatable {
  var enabled = false
  var owner: String?
  var libraryName = "Library"
  var accountLibraries: [String: String] = [:]

  static let containerIdentifier = "iCloud.chat.eastechs.tapster"

  static func accountKey(_ recordName: String) -> String {
    SHA256.hash(data: Data(recordName.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  func changingSync(to enabled: Bool, account: CloudAccount) throws -> Self {
    var next = self
    if enabled {
      guard case .available(let id) = account else {
        throw TemplateError.invalid(
          "Sign in to iCloud and check your connection before enabling sync.")
      }
      if let owner, owner != id {
        // Another account gets a separate library, never an implicit copy of this account's data.
        next.libraryName = accountLibraries[id] ?? UUID().uuidString
      }
      next.owner = id
      next.accountLibraries[id] = next.libraryName
    }
    next.enabled = enabled
    return next
  }

  func canSync(with account: CloudAccount) -> Bool {
    guard enabled, let owner, case .available(let id) = account else { return false }
    return owner == id
  }

  func storeURL(in directory: URL) throws -> URL {
    guard libraryName == "Library" || UUID(uuidString: libraryName) != nil else {
      throw TemplateError.invalid("The saved iCloud library location is invalid.")
    }
    return directory.appendingPathComponent(libraryName + ".store")
  }

  static func directory() throws -> URL {
    var url = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    ).appendingPathComponent("chat.eastechs.tapster")
    #if DEBUG
      url.appendPathComponent("Development")
    #else
      if ProcessInfo.processInfo.arguments.contains("--sync-preview") {
        url.appendPathComponent("ProductionPreview")
      }
    #endif
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  static func load(in directory: URL) throws -> Self {
    let url = directory.appendingPathComponent("SyncConfiguration.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }

  func save(in directory: URL) throws {
    let url = directory.appendingPathComponent("SyncConfiguration.json")
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
