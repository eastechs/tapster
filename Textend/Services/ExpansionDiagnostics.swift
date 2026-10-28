import OSLog

enum ExpansionDiagnostics {
  private static let logger = Logger(subsystem: BuildIdentity.bundleID, category: "Expansion")

  /// Development diagnostics contain only fixed reasons and process IDs, never input text.
  static func record(_ reason: String, processID: Int32) {
    #if DEBUG
      logger.info("\(reason, privacy: .public); pid=\(processID)")
    #endif
  }
}
