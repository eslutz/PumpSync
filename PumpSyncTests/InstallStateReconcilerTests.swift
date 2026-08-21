import XCTest
@testable import PumpSync

final class InstallStateReconcilerTests: XCTestCase {
  private let currentBackendSessionAccount = "backend.session.current"

  func testFreshInstallCleanupIsScopedToPumpSyncKeychainService() throws {
    let appKeychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.app.\(UUID().uuidString)")
    let unrelatedKeychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.other.\(UUID().uuidString)")
    try appKeychain.writeData(Data("credential".utf8), account: "tandem-source-credentials")
    try appKeychain.writeData(Data("session".utf8), account: currentBackendSessionAccount)
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
    XCTAssertEqual(try unrelatedKeychain.readData(account: "unrelated"), Data("keep".utf8))
  }

  func testFreshInstallClearsAppKeychainBeforeRecordingInstallationState() throws {
    let suiteName = "InstallStateReconcilerTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    var cleanupCount = 0

    let result = try InstallStateReconciler.reconcile(defaults: defaults) {
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

    let result = try InstallStateReconciler.reconcile(defaults: defaults) {
      cleanupCount += 1
    }

    XCTAssertEqual(result, .existingInstall)
    XCTAssertEqual(cleanupCount, 0)
  }
}
