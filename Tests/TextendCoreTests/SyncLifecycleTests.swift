import XCTest

@testable import TextendCore

@MainActor private final class TestCloudAccount: CloudAccountProviding {
  var isProvisioned = true
  var account: CloudAccount = .available("account-a")
  func currentAccount() async -> CloudAccount { account }
}

final class SyncLifecycleTests: XCTestCase {
  func testConfigurationRequiresExplicitAccountSelectionAndRetainsSeparateLibraries() throws {
    let initial = SyncConfiguration()
    XCTAssertFalse(initial.enabled)
    let a = try initial.changingSync(to: true, account: .available("a"))
    XCTAssertEqual(a.libraryName, "Library")
    XCTAssertFalse(a.canSync(with: .available("b")))
    XCTAssertFalse(a.canSync(with: .signedOut))
    let disabled = try a.changingSync(to: false, account: .signedOut)
    XCTAssertEqual(disabled.libraryName, a.libraryName)
    XCTAssertEqual(disabled.owner, "a")
    let b = try disabled.changingSync(to: true, account: .available("b"))
    XCTAssertNotEqual(b.libraryName, a.libraryName)
    XCTAssertEqual(
      try b.changingSync(to: true, account: .available("a")).libraryName, a.libraryName)
    XCTAssertThrowsError(try initial.changingSync(to: true, account: .unavailable("Offline")))
    var invalid = initial
    invalid.libraryName = "../Library"
    XCTAssertThrowsError(try invalid.storeURL(in: URL(fileURLWithPath: "/tmp")))
  }

  @MainActor func testRestartCancellationOfflineEditingAndAccountRecovery() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "TextendSyncTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let provider = TestCloudAccount()
    var cloudRequests: [String?] = []
    let factory: @MainActor (URL, String?) throws -> LibraryStore = { url, container in
      cloudRequests.append(container)
      return try LibraryStore(url: url)
    }
    let first = try SyncCoordinator(
      directory: directory, provider: provider, defaults: defaults, makeStore: factory)
    let local = try await first.openLibrary()
    XCTAssertTrue(local.snippets.isEmpty)
    let record = SnippetRecord(name: "Local", keyword: "one", template: "Kept")
    try local.save(record)
    let saved = try XCTUnwrap(local.snippets.first)
    var proposed: SyncConfiguration?
    first.onRestart = { proposed = $0 }
    first.requestChange(true)
    XCTAssertNotNil(proposed)
    XCTAssertFalse(
      try SyncConfiguration.load(in: directory).enabled,
      "Cancelling restart must not persist a request")
    try first.commitForRestart(XCTUnwrap(proposed))
    try first.rollbackRestart()
    XCTAssertFalse(try SyncConfiguration.load(in: directory).enabled)
    try first.commitForRestart(XCTUnwrap(proposed))
    first.stop()
    local.suspend()

    let synced = try SyncCoordinator(
      directory: directory, provider: provider, defaults: defaults, makeStore: factory)
    let active = try await synced.openLibrary()
    XCTAssertTrue(synced.isActive)
    XCTAssertEqual(cloudRequests.last!, SyncConfiguration.containerIdentifier)
    XCTAssertEqual(active.snippets, [saved])
    provider.account = .unavailable("Offline")
    await synced.checkAccount()
    XCTAssertFalse(synced.requiresRestart)
    XCTAssertFalse(active.isSuspended)
    var edited = record
    edited.template = "Offline edit"
    try active.save(edited)
    provider.account = .available("account-b")
    await synced.checkAccount()
    XCTAssertTrue(synced.requiresRestart)
    XCTAssertTrue(active.isSuspended)
    XCTAssertTrue(active.expansionSnippets.isEmpty)
    XCTAssertFalse(synced.recoveryFailed)
    XCTAssertFalse(try SyncConfiguration.load(in: directory).enabled)
    synced.stop()

    let recovered = try SyncCoordinator(
      directory: directory, provider: provider, defaults: defaults, makeStore: factory)
    let recovery = try await recovered.openLibrary()
    XCTAssertFalse(recovered.isActive)
    XCTAssertNil(cloudRequests.last!)
    XCTAssertEqual(recovery.snippets.first?.template, "Offline edit")
    let nextAccount = try recovered.configuration.changingSync(to: true, account: provider.account)
    XCTAssertNotEqual(nextAccount.libraryName, recovered.configuration.libraryName)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: try nextAccount.storeURL(in: directory).path))
    recovered.stop()
  }
  @MainActor func testRecoveryFailureBlocksRestartAndKeepsLibraryExportable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = try SyncConfiguration().changingSync(
      to: true, account: .available("account-a"))
    try configuration.save(in: directory)
    let provider = TestCloudAccount()
    let suite = "TextendSyncTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let sync = try SyncCoordinator(
      directory: directory, provider: provider, defaults: defaults,
      makeStore: { url, _ in try LibraryStore(url: url) })
    defer { sync.stop() }
    let store = try await sync.openLibrary()
    try store.save(.init(name: "Keep", keyword: "keep", template: "Recoverable"))
    let configURL = directory.appendingPathComponent("SyncConfiguration.json")
    try FileManager.default.removeItem(at: configURL)
    try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
    provider.account = .signedOut
    await sync.checkAccount()
    XCTAssertTrue(sync.recoveryFailed)
    XCTAssertTrue(store.isSuspended)
    XCTAssertEqual(store.archive.snippets.first?.template, "Recoverable")
    XCTAssertNoThrow(try store.recoveryData())
    var restarted = false
    sync.onRestart = { _ in restarted = true }
    sync.requestChange(false)
    XCTAssertFalse(restarted)
  }

}
