import XCTest
@testable import PumpSync

@MainActor
final class SyncHistoryOwnershipTests: XCTestCase {
  func testRecentSyncsUseScopedCompletedRunsWithoutDuplicatingTheMetadataResult() throws {
    let success = Date(timeIntervalSince1970: 120)
    var metadata = SyncMetadata(lastAttemptAt: nil, lastSuccessfulSyncAt: success, lastSampleCount: 5,
                                lastImportedCount: 4, lastErrorMessage: nil, initialImportRange: .pastTwoWeeks)
    let scope = metadata.historyScopeID
    let latest = SyncAttempt(operationID: UUID(), trigger: .manual, startedAt: success.addingTimeInterval(-2),
                             stage: .terminal, outcome: .completed, historyScopeID: scope,
                             completedAt: success.addingTimeInterval(1), returnedCount: 5, importedCount: 4)
    var earlier = SyncAttempt(operationID: UUID(), trigger: .manual, startedAt: success.addingTimeInterval(-30),
                              stage: .terminal, outcome: .completed, historyScopeID: scope,
                              completedAt: success.addingTimeInterval(-20), returnedCount: 0, importedCount: 0)
    var failed = earlier
    failed.outcome = .failed
    var skipped = earlier
    skipped.outcome = .skipped
    var differentAccount = earlier
    differentAccount.historyScopeID = UUID()
    let attempts = [earlier, failed, skipped, differentAccount, latest]
    let rows = RecentSync.retained(metadata: metadata, attempts: attempts)
    XCTAssertEqual(rows.map(\.id), [
      .attempt(scope: scope, operation: latest.operationID), .attempt(scope: scope, operation: earlier.operationID)
    ])
    XCTAssertEqual(rows.map(\.summary), ["4 samples saved to Apple Health", "No new samples"])
    XCTAssertEqual(RecentSync.retained(metadata: metadata, attempts: [earlier]).first?.id,
                   .latestSuccess(scope: scope, completedAt: success))

    earlier.importedCount = nil
    XCTAssertEqual(RecentSync.retained(metadata: metadata, attempts: [earlier]).last?.summary, "Saved count unavailable")
    metadata.historyScopeID = UUID()
    metadata.lastSuccessfulSyncAt = nil
    XCTAssertTrue(RecentSync.retained(metadata: metadata, attempts: attempts).isEmpty)
  }

  func testRecentSyncDayGroupsUseLocalMidnight() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22)))
    let now = midnight.addingTimeInterval(60)
    let scope = UUID()
    let runs = [now, midnight.addingTimeInterval(-60), midnight.addingTimeInterval(-90)].map {
      RecentSync(id: .attempt(scope: scope, operation: UUID()), completedAt: $0, returned: 0,
                 saved: 0, permissionSkipped: 0)
    }
    let days = RecentSyncDay.groups(for: runs, calendar: calendar)
    XCTAssertEqual(days.map { $0.title(now: now, calendar: calendar) }, ["Today", "Yesterday"])
    XCTAssertEqual(days.map(\.runs), [[runs[0]], [runs[1], runs[2]]])
  }

  func testLegacyFailureWithoutOwnershipIsNeverAssignedToANewAccount() {
    let suite = "UnboundError.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data(#"{"lastSampleCount":0,"lastImportedCount":0,"lastErrorMessage":"Earlier failure"}"#.utf8), forKey: "sync-metadata")
    let store = SyncMetadataStore(defaults: defaults)
    store.reconcileOwner(TandemSyncOwner(accountId: UUID()))
    XCTAssertNil(store.metadata.latestFailure)
    XCTAssertEqual(store.metadata.cursorResetReason, .legacyUnbound)
  }

  func testFailedAtomicLegacyMigrationDefersOwnershipWithoutClearingBoundHistory() throws {
    let persistence = FailingTandemPersistence()
    defer { try? persistence.keychain.deleteAll() }
    let credentials = TandemCredentials(username: "legacy", password: "fixture", region: "us")
    let accountId = UUID()
    try persistence.writeData(JSONEncoder().encode(credentials), account: "tandem-source-credentials")
    let validation = try JSONSerialization.data(withJSONObject: ["username": credentials.username, "region": credentials.region, "validatedAt": 100, "status": "validated", "accountId": accountId.uuidString])
    try persistence.writeData(validation, account: "tandem-source-credential-validation")
    let suite = "FailedAtomicMigration.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let owner = TandemSyncOwner(accountId: accountId, backendIdentity: "https://real.example/api")
    let metadata = SyncMetadataStore(defaults: defaults)
    metadata.recordSuccess(sampleCount: 4, importedCount: 3, completedAt: Date(), watermark: Date(timeIntervalSince1970: 100), owner: owner)
    let previous = metadata.metadata
    persistence.failWriteAccount = "tandem-source-credentials"
    let failed = TandemCredentialStore(keychain: persistence)
    XCTAssertFalse(failed.ownershipAvailable)
    XCTAssertFalse(failed.hasValidatedCredentials)
    XCTAssertEqual(try persistence.readData(account: "tandem-source-credential-validation"), validation)
    XCTAssertEqual(SyncMetadataStore(defaults: defaults).metadata, previous)
    persistence.failWriteAccount = nil
    let migrated = TandemCredentialStore(keychain: persistence)
    XCTAssertTrue(migrated.ownershipAvailable)
    XCTAssertFalse(migrated.hasValidatedCredentials)
    XCTAssertTrue(migrated.needsDirectReconnect)
    XCTAssertEqual(migrated.accountId, accountId)
    metadata.reconcileOwner(TandemSyncOwner(accountId: try XCTUnwrap(migrated.accountId), backendIdentity: owner.backendIdentity))
    XCTAssertEqual(metadata.metadata, previous)
  }

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

  func testLegacyCursorAdoptedOnlyForSameAccountFromKnownHostedService() throws {
    for endpoint in ["https://api.pumpsync.ericslutz.dev/api", "https://custom.example/api"] {
      for sameAccount in [true, false] {
        let defaults = UserDefaults(suiteName: "DirectUpgrade.\(UUID())")!
        let store = SyncMetadataStore(defaults: defaults)
        let account = UUID()
        let cursor = Date(timeIntervalSince1970: 100)
        let previous = TandemSyncOwner(accountId: account, backendIdentity: endpoint)
        store.recordSuccess(sampleCount: 10, importedCount: 4, completedAt: cursor, watermark: cursor, owner: previous)
        store.setInitialImportRange(.pastTwoDays)
        let owner = TandemSyncOwner(accountId: sameAccount ? account : UUID())
        store.reconcileOwner(owner)
        let expectCursor = sameAccount && endpoint == "https://api.pumpsync.ericslutz.dev/api"
        XCTAssertEqual(store.metadata.syncWatermark, expectCursor ? cursor : nil)
        XCTAssertEqual(store.metadata.initialImportRange, .pastTwoDays)
        let migrated = store.metadata
        let restarted = SyncMetadataStore(defaults: defaults)
        restarted.reconcileOwner(owner)
        XCTAssertEqual(restarted.metadata, migrated)
      }
    }
  }

  func testLegacyValidationMigrationPersistsAccountIdentityWithoutBlessingLegacyCursor() throws {
    let keychain = SecureKeychainStore(service: "LegacyValidation.\(UUID().uuidString)")
    defer { try? keychain.deleteAll() }
    try keychain.writeData(JSONEncoder().encode(TandemCredentials(username: "legacy", password: "fixture", region: "us")), account: "tandem-source-credentials")
    try keychain.writeData(Data(#"{"username":"legacy","region":"us","validatedAt":100}"#.utf8), account: "tandem-source-credential-validation")
    let migrated = TandemCredentialStore(keychain: keychain)
    XCTAssertFalse(migrated.hasValidatedCredentials)
    XCTAssertTrue(migrated.needsDirectReconnect)
    let owner = try XCTUnwrap(migrated.accountId)
    XCTAssertEqual(TandemCredentialStore(keychain: keychain).accountId, owner)
    migrated.invalidateValidation()
    let restarted = TandemCredentialStore(keychain: keychain)
    XCTAssertFalse(restarted.hasValidatedCredentials)
    XCTAssertEqual(restarted.accountId, owner)
  }
}
