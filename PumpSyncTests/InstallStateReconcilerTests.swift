import XCTest
@testable import PumpSync

final class InstallStateReconcilerTests: XCTestCase {
  private let currentBackendSessionAccount = "backend.session.current"

  func testFreshInstallCleanupIsScopedToPumpSyncKeychainService() throws {
    let appKeychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.app.\(UUID().uuidString)")
    let unrelatedKeychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.other.\(UUID().uuidString)")
    try appKeychain.writeData(Data("credential".utf8), account: "tandem-source-credentials")
    try appKeychain.writeData(Data("session".utf8), account: currentBackendSessionAccount)
    let recoveryAccounts = ["backend.auth.operation-journal.v1", "backend.auth.invalidation.v1", "backend.auth.invalidation-fallback.v1"]
    for account in recoveryAccounts { try appKeychain.writeData(Data("recovery-metadata".utf8), account: account) }
    try unrelatedKeychain.writeData(Data("keep".utf8), account: "unrelated")
    defer {
      try? appKeychain.deleteAll()
      try? unrelatedKeychain.deleteAll()
    }

    let defaults = UserDefaults(suiteName: "InstallStateReconcilerTests-\(UUID().uuidString)")!
    _ = try InstallStateReconciler.reconcile(defaults: defaults) {
      try appKeychain.deleteAll()
    }

    XCTAssertNil(try appKeychain.readData(account: "tandem-source-credentials"))
    XCTAssertNil(try appKeychain.readData(account: currentBackendSessionAccount))
    for account in recoveryAccounts { XCTAssertNil(try appKeychain.readData(account: account)) }
    XCTAssertEqual(try unrelatedKeychain.readData(account: "unrelated"), Data("keep".utf8))
  }

  func testFreshInstallClearsAppKeychainBeforeRecordingInstallationState() throws {
    let suiteName = "InstallStateReconcilerTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var cleanupCount = 0

    let result = InstallStateReconciler.reconcile(defaults: defaults) {
      cleanupCount += 1
    }

    XCTAssertEqual(result, .freshInstall)
    XCTAssertEqual(cleanupCount, 1)
  }

  func testUpgradePreservesKeychainWhenInstallationIdExists() throws {
    let suiteName = "InstallStateReconcilerTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("existing-installation", forKey: BackendConfigurationStore.installationIdDefaultsKey)
    var cleanupCount = 0

    let result = InstallStateReconciler.reconcile(defaults: defaults) {
      cleanupCount += 1
    }

    XCTAssertEqual(result, .existingInstall)
    XCTAssertEqual(cleanupCount, 0)
  }
}
