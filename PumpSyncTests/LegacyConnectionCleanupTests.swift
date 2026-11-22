import XCTest
@testable import PumpSync

final class LegacyConnectionCleanupTests: XCTestCase {
  func testUpgradeRemovesOnlyServiceCredentialsAndPreservesDeletionReference() throws {
    let service = UUID().uuidString
    let keychain = SecureKeychainStore(service: service)
    let defaults = try XCTUnwrap(UserDefaults(suiteName: service))
    defer {
      try? keychain.deleteAll()
      defaults.removePersistentDomain(forName: service)
    }
    let retained = ["tandem-source-credentials", "imported-sample-ledger-hmac-key"]
    let retired = ["backend.session.current", "connection." + service + ".backend.session.current", "device-proof.app-attest-state.v4"]
    for account in retained + retired { try keychain.writeData(Data([1]), account: account) }
    defaults.set(service, forKey: "backend.installationId")
    defaults.set("legacy", forKey: "backend.mode")
    try LegacyConnectionCleanup.run(in: keychain, defaults: defaults)
    try LegacyConnectionCleanup.run(in: keychain, defaults: defaults)
    for account in retained { XCTAssertEqual(try keychain.readData(account: account), Data([1])) }
    for account in retired { XCTAssertNil(try keychain.readData(account: account)) }
    XCTAssertNil(defaults.string(forKey: "backend.mode"))
    XCTAssertEqual(AppConstants.legacyInstallationID(defaults: defaults), service)
  }
}
