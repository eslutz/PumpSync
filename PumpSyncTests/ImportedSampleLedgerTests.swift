import XCTest
import Security
@testable import PumpSync

final class ImportedSampleLedgerTests: XCTestCase {
  func testFilterUnseenExcludesAlreadyImportedSamples() throws {
    let ledger = makeLedger()
    let seen = sample(externalId: "sample-1")
    let unseen = sample(externalId: "sample-2")
    try ledger.recordImported([seen])

    let result = try ledger.filterUnseen([seen, unseen])

    XCTAssertEqual(result.map(\.externalId), ["sample-2"])
  }

  func testRecordImportedIsIdempotent() throws {
    let ledger = makeLedger()
    let sample = sample(externalId: "sample-1")

    try ledger.recordImported([sample])
    try ledger.recordImported([sample])

    XCTAssertEqual(try ledger.filterUnseen([sample]).count, 0)
  }

  func testDigestsAreStableAcrossLedgerInstancesSharingAKeychainAndDefaults() throws {
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: "ImportedSampleLedgerTests-\(UUID().uuidString)")!
    let sample = sample(externalId: "sample-1")

    let first = ImportedSampleLedger(keychain: keychain, defaults: defaults)
    try first.recordImported([sample])

    // A fresh instance against the same keychain/defaults must bootstrap the
    // same HMAC key rather than generating a new one, or every relaunch
    // would silently forget what's already been imported and re-deliver it.
    let second = ImportedSampleLedger(keychain: keychain, defaults: defaults)
    let result = try second.filterUnseen([sample])

    XCTAssertTrue(result.isEmpty)
  }

  func testMigratingLegacyHmacKeyPreservesKeyAndMakesItAvailableAfterFirstUnlock() throws {
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)")
    let keyData = Data(repeating: 0x42, count: 32)
    let account = "imported-sample-ledger-hmac-key"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychain.service,
      kSecAttrAccount as String: account,
      kSecValueData as String: keyData,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
    defer { try? keychain.deleteAll() }

    let ledger = ImportedSampleLedger(
      keychain: keychain,
      defaults: UserDefaults(suiteName: "ImportedSampleLedgerTests-\(UUID().uuidString)")!
    )

    try ledger.migrateHmacKeyForBackgroundAccess()

    XCTAssertEqual(try keychain.readData(account: account), keyData)
    XCTAssertEqual(
      try accessibility(of: keychain, account: account),
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
  }

  func testPruneDropsEntriesOlderThanRetentionWindow() throws {
    let ledger = makeLedger()
    let stale = sample(externalId: "stale-sample")
    let fresh = sample(externalId: "fresh-sample")
    let importedAt = Date(timeIntervalSince1970: 1_000_000)

    try ledger.recordImported([stale], importedAt: importedAt)
    // 370 days + a margin, matching the ledger's retention window.
    try ledger.recordImported([fresh], importedAt: importedAt.addingTimeInterval(371 * 24 * 60 * 60))

    let result = try ledger.filterUnseen([stale, fresh])

    XCTAssertEqual(result.map(\.externalId), ["stale-sample"], "the stale entry should have been pruned out of the ledger and treated as unseen again")
  }

  func testPruneCapsRetainedEntriesToNewestByTimestamp() throws {
    // Every digest computed by the real ledger does its own Keychain round
    // trip (see ImportedSampleLedger.hmacKeyData()), so driving 5000+ entries
    // through the real recordImported/keychain path would make this single
    // test take tens of seconds. Seed the bulk of the entries directly into
    // the same UserDefaults-backed dictionary the ledger reads/writes
    // instead, and only exercise the real digest path for the one sample
    // actually under test — prune() itself operates purely on the stored
    // timestamp values, so it doesn't care whether a key came from a real
    // HMAC digest or a placeholder.
    let defaultsKey = "imported-sample-ledger"
    let defaults = UserDefaults(suiteName: "ImportedSampleLedgerTests-\(UUID().uuidString)")!
    let baseTimestamp: TimeInterval = 1_000_000
    let seeded = Dictionary(uniqueKeysWithValues: (0..<5000).map { ("dummy-\($0)", baseTimestamp + Double($0)) })
    defaults.set(seeded, forKey: defaultsKey)

    let ledger = ImportedSampleLedger(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      defaults: defaults
    )
    try ledger.recordImported([sample(externalId: "newest-sample")], importedAt: Date(timeIntervalSince1970: baseTimestamp + 10_000))

    let stored = defaults.dictionary(forKey: defaultsKey) as? [String: TimeInterval]

    XCTAssertEqual(stored?.count, 5000, "the ledger should still be capped at its 5000-entry limit")
    XCTAssertNil(stored?["dummy-0"], "the oldest entry should have been evicted to make room for the new one")
    XCTAssertNotNil(stored?["dummy-4999"], "recently-seen entries should be retained over older ones")
  }

  private func makeLedger() -> ImportedSampleLedger {
    ImportedSampleLedger(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      defaults: UserDefaults(suiteName: "ImportedSampleLedgerTests-\(UUID().uuidString)")!
    )
  }

  private func accessibility(of keychain: SecureKeychainStore, account: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychain.service,
      kSecAttrAccount as String: account,
      kSecReturnAttributes as String: kCFBooleanTrue,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
    return (result as? [String: Any])?[kSecAttrAccessible as String] as? String
  }

  private func sample(externalId: String) -> SampleDTO {
    SampleDTO(
      externalId: externalId,
      type: "insulin.bolus",
      value: 1,
      unit: "IU",
      startAt: Date(timeIntervalSince1970: 1_000),
      endAt: Date(timeIntervalSince1970: 1_060),
      metadata: [:],
      source: SourceDTO(deviceId: "pump-1", eventIds: ["1"])
    )
  }
}
