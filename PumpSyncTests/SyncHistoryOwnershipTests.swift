import XCTest
@testable import PumpSync

@MainActor
final class SyncHistoryOwnershipTests: XCTestCase {
  func testLegacyCursorMigrationBeforeAndAfterCredentialReplacementPreservesLiveLedgerAndPreferences() throws {
    for replaceBeforeMigration in [false, true] {
      let suite = "HistoryMigration.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let keychain = SecureKeychainStore(service: suite)
      defer { try? keychain.deleteAll() }
      let credentials = TandemCredentialStore(keychain: keychain)
      try credentials.saveValidated(.init(username: "original", password: "fixture", region: "us"))
      let ledgerBytes = ["existing-digest": 123.0]
      defaults.set(ledgerBytes, forKey: "imported-sample-ledger")
      let concentration = InsulinConcentrationStore(defaults: defaults)
      concentration.concentration = .u500
      let preference = defaults.string(forKey: "insulinConcentration")
      // This is the actual pre-ownership on-disk shape, not a newly bound fixture.
      defaults.set(Data(#"{"lastAttemptAt":10,"lastSuccessfulSyncAt":20,"lastSampleCount":7,"lastImportedCount":6,"syncWatermark":15,"initialImportRange":"pastTwoWeeks"}"#.utf8), forKey: "sync-metadata")
      if replaceBeforeMigration { try credentials.saveValidated(.init(username: "replacement", password: "fixture", region: "us")) }
      let metadata = SyncMetadataStore(defaults: defaults)
      let owner = TandemSyncOwner(accountId: try XCTUnwrap(credentials.accountId), backendIdentity: "https://real.example/api")
      metadata.reconcileOwner(owner)
      XCTAssertNil(metadata.metadata.syncWatermark)
      XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
      XCTAssertEqual(metadata.metadata.lastSampleCount, 0)
      XCTAssertEqual(metadata.metadata.lastImportedCount, 0)
      XCTAssertEqual(metadata.metadata.initialImportRange, .pastTwoWeeks)
      XCTAssertEqual(metadata.metadata.cursorResetReason, .legacyUnbound)
      XCTAssertEqual(defaults.dictionary(forKey: "imported-sample-ledger") as? [String: Double], ledgerBytes)
      XCTAssertEqual(defaults.string(forKey: "insulinConcentration"), preference)
      XCTAssertEqual(InsulinConcentrationStore(defaults: defaults).concentration, .u500)
      XCTAssertNil(SyncMetadataStore(defaults: defaults).metadata.syncWatermark)
    }
  }

  func testDurablyBoundCursorSurvivesRestartAndSameOwnerReconciliation() throws {
    let suite = "BoundHistory.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let owner = TandemSyncOwner(accountId: UUID(), backendIdentity: "https://real.example/api")
    let store = SyncMetadataStore(defaults: defaults)
    store.recordSuccess(sampleCount: 4, importedCount: 3, completedAt: Date(timeIntervalSince1970: 100), watermark: Date(timeIntervalSince1970: 90), owner: owner)
    let persisted = try XCTUnwrap(defaults.data(forKey: "sync-metadata"))
    let restarted = SyncMetadataStore(defaults: defaults)
    restarted.reconcileOwner(owner)
    XCTAssertEqual(restarted.metadata, store.metadata)
    XCTAssertEqual(defaults.data(forKey: "sync-metadata"), persisted)
  }

  func testLegacyValidationMigrationPersistsAccountIdentityWithoutBlessingLegacyCursor() throws {
    let keychain = SecureKeychainStore(service: "LegacyValidation.\(UUID().uuidString)")
    defer { try? keychain.deleteAll() }
    try keychain.writeData(JSONEncoder().encode(TandemCredentials(username: "legacy", password: "fixture", region: "us")), account: "tandem-source-credentials")
    try keychain.writeData(Data(#"{"username":"legacy","region":"us","validatedAt":100}"#.utf8), account: "tandem-source-credential-validation")
    let migrated = TandemCredentialStore(keychain: keychain)
    XCTAssertTrue(migrated.hasValidatedCredentials)
    let owner = try XCTUnwrap(migrated.accountId)
    XCTAssertEqual(TandemCredentialStore(keychain: keychain).accountId, owner)
    migrated.invalidateValidation()
    let restarted = TandemCredentialStore(keychain: keychain)
    XCTAssertFalse(restarted.hasValidatedCredentials)
    XCTAssertEqual(restarted.accountId, owner)
  }
}
