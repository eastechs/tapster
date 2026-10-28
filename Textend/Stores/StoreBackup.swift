import Foundation
import SQLite3

enum StoreBackup {
  /// SQLite's backup API includes committed WAL contents without copying a live file set.
  static func beforeMigration(at source: URL) throws {
    guard FileManager.default.fileExists(atPath: source.path) else { return }
    let destination = source.appendingPathExtension("pre-v3.sqlite")
    guard !FileManager.default.fileExists(atPath: destination.path) else { return }
    let temporary = destination.appendingPathExtension(UUID().uuidString)
    var input: OpaquePointer?
    var output: OpaquePointer?
    defer {
      if let input { sqlite3_close(input) }
      if let output { sqlite3_close(output) }
      try? FileManager.default.removeItem(at: temporary)
    }
    guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
      sqlite3_open(temporary.path, &output) == SQLITE_OK,
      let backup = sqlite3_backup_init(output, "main", input, "main")
    else { throw failure() }
    var result = sqlite3_backup_step(backup, -1)
    for _ in 0..<20 where result == SQLITE_BUSY || result == SQLITE_LOCKED {
      Thread.sleep(forTimeInterval: 0.025)
      result = sqlite3_backup_step(backup, -1)
    }
    let finished = sqlite3_backup_finish(backup)
    guard result == SQLITE_DONE, finished == SQLITE_OK else {
      throw TemplateError.invalid(
        "Couldn’t back up the library (SQLite \(result)/\(finished)). Your existing library has not been replaced."
      )
    }
    sqlite3_close(output)
    output = nil
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
    try FileManager.default.moveItem(at: temporary, to: destination)
  }

  private static func failure() -> Error {
    TemplateError.invalid(
      "Couldn’t back up the library before migration. Close other Textend copies and try again. Your existing library has not been replaced."
    )
  }
}
