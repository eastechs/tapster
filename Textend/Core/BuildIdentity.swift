import Foundation

/// Production identifiers remain stable for updates, TCC permissions, and saved data.
enum BuildIdentity {
  static let productionBundleID = "chat.eastechs.tapster"
  static let developmentBundleID = "chat.eastechs.textend.debug"
  static let applicationBundleIDs: Set<String> = [productionBundleID, developmentBundleID]

  #if DEBUG
    static let bundleID = developmentBundleID
    static let displayName = "Textend Dev"
  #else
    static let bundleID = productionBundleID
    static let displayName = "Textend"
  #endif
}
