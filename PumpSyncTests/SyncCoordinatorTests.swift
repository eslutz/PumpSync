import HealthKit
import XCTest
@testable import PumpSync

@MainActor
private final class FakeHealthKitService: SyncHealthWriting {
  var hasAnyWritePermission: Bool
  var saveError: Error?
  var concentration: InsulinConcentration = .u100
  private(set) var savedConcentrations: [InsulinConcentration] = []
  /// External ids save() should silently drop, mirroring HealthKitService
  /// skipping samples whose per-type permission is missing.
  var droppedExternalIds: Set<String> = []
  private(set) var refreshAuthorizationStatusCallCount = 0
  private(set) var savedSamples: [SampleDTO] = []
  var saveStarted: (() -> Void)?
  var suspendsSave = false
  private var saveContinuation: CheckedContinuation<Void, Never>?

  init(hasAnyWritePermission: Bool = true) {
    self.hasAnyWritePermission = hasAnyWritePermission
  }

  func refreshAuthorizationStatus() {
    refreshAuthorizationStatusCallCount += 1
  }

  func save(batch: HealthImportBatch) async throws -> [SampleDTO] {
    let samples = batch.plan.samples.map(\.original)
    let concentration = batch.plan.concentration
    savedConcentrations.append(concentration)
    savedSamples = samples
    saveStarted?()
    if suspendsSave {
      await withCheckedContinuation { continuation in
        saveContinuation = continuation
      }
    }
    if let saveError {
      throw saveError
    }

    return samples.filter { !droppedExternalIds.contains($0.externalId) }
  }

  func resumeSave() {
    saveContinuation?.resume()
    saveContinuation = nil
  }
}

@MainActor
private final class SubmissionRecordingHealthPersistence: HealthSamplePersisting {
  private(set) var saved: [HKQuantitySample] = []
  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus { .sharingAuthorized }
  func save(_ samples: [HKQuantitySample], completion: @escaping @Sendable (Bool, Error?) -> Void) {
    saved.append(contentsOf: samples)
    completion(true, nil)
  }
}

private final class FailingSyncSampleLedger: SyncSampleLedger {
  private(set) var commitCount = 0
  func filterUnseen(_ samples: [SampleDTO]) throws -> [SampleDTO] { samples }
  func recordImported(_ samples: [SampleDTO], importedAt: Date) throws {
    commitCount += 1
    throw KeychainStoreError.invalidData
  }
}

@MainActor
final class SyncCoordinatorTests: XCTestCase {
  private let credentials = TandemCredentials(username: "fixture", password: "fixture", region: "us")
  private let boundary = Date().addingTimeInterval(-600)
  private let suite = "SyncCoordinator.\(UUID())"
  private var keychain: SecureKeychainStore { SecureKeychainStore(service: suite) }
  private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
  private var account: TandemCredentialStore!
  private var ledger: ImportedSampleLedger!
  private var metadata: SyncMetadataStore!
  private var health: FakeHealthKitService!
  private var source: DirectImportTestSource!
  private var coordinator: SyncCoordinator!

  private func prepare(samples: [SampleDTO] = [], held: Bool = false, validated: Bool = true, mode: DataSourceMode = .tandemSource) throws {
    account = TandemCredentialStore(keychain: keychain)
    if validated { try account.saveValidated(credentials) }
    ledger = ImportedSampleLedger(keychain: keychain, defaults: defaults)
    metadata = SyncMetadataStore(defaults: defaults)
    health = FakeHealthKitService()
    source = DirectImportTestSource(.success(.init(samples: samples, effectiveMinDate: boundary.addingTimeInterval(-86400), effectiveMaxDate: boundary, dataSourceMode: mode)), held: held)
    coordinator = makeCoordinator(health: health, ledger: ledger)
    addTeardownBlock { @MainActor [self] in
      try keychain.deleteAll()
      defaults.removePersistentDomain(forName: suite)
    }
  }

  private func makeCoordinator(health: any SyncHealthWriting, ledger: any SyncSampleLedger) -> SyncCoordinator {
    let result = SyncCoordinator(dataSource: source, credentialStore: account, healthKitService: health, importedSampleLedger: ledger, syncMetadataStore: metadata, attemptStore: SyncAttemptStore(defaults: defaults))
    result.setForegroundActive(true)
    return result
  }

  private func sample(_ id: String) -> SampleDTO {
    SampleDTO(externalId: id, type: "insulin.bolus", value: 1.5, unit: "IU", startAt: boundary, endAt: boundary, metadata: [:], source: SourceDTO(deviceId: "fixture", eventIds: [id]))
  }

  private func grant() -> SyncExecutionLease {
    SyncExecutionLease(kind: .background, deadline: Date().addingTimeInterval(5))
  }

  private func until(_ condition: () async -> Bool) async throws {
    for _ in 0..<500 {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(2))
    }
    XCTFail("Timed out waiting for the controlled import stage")
  }

  func testConfirmedWritesAdvanceFromEffectiveWindowAndRepeatDeduplicates() async throws {
    try prepare(samples: [sample("bolus")])
    let first = await coordinator.run(reason: .manual)
    XCTAssertEqual(first, .completed)
    XCTAssertEqual(metadata.metadata.syncWatermark, boundary.addingTimeInterval(-86400))
    XCTAssertEqual(metadata.metadata.lastImportedCount, 1)
    let second = await coordinator.run(reason: .manual)
    XCTAssertEqual(second, .completed)
    XCTAssertEqual(health.savedSamples.count, 0)
    XCTAssertEqual(metadata.metadata.lastImportedCount, 0)
    let requests = await source.requests
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests.last?.timeZoneIdentifier, TimeZone.current.identifier)
    XCTAssertEqual(requests.last?.minDate, metadata.metadata.syncWatermark)
    XCTAssertEqual(coordinator.attemptStore.history.first?.importCheckpoint, .metadataCommitted)
  }

  func testFreshnessSkipsAppOpenAndGrantedBackgroundStillImports() async throws {
    try prepare()
    let initial = await coordinator.refreshIfStale(reason: .appOpen)
    XCTAssertEqual(initial, .completed)
    let fresh = await coordinator.reconcileForegroundRecovery()
    XCTAssertEqual(fresh, .skippedFresh)
    let before = await source.callCount
    XCTAssertEqual(before, 1)
    coordinator.setForegroundActive(false)
    let background = await coordinator.performBackgroundSync(lease: grant())
    XCTAssertTrue(background)
    XCTAssertEqual(coordinator.operationState, .idle)
    let after = await source.callCount
    XCTAssertEqual(after, 2)
  }

  func testStaleAppOpenStartsDownloadFromOldWatermark() async throws {
    try prepare()
    let old = Date().addingTimeInterval(-5 * 3600)
    let owner = TandemSyncOwner(accountId: try XCTUnwrap(account.accountId))
    metadata.recordSuccess(sampleCount: 4, importedCount: 0, completedAt: old, watermark: old, owner: owner)
    let result = await coordinator.reconcileForegroundRecovery()
    let request = await source.requests.first
    XCTAssertEqual(result, .completed)
    XCTAssertEqual(request?.minDate, old)
  }

  func testOldCursorDisplaysLocalImportLimitWhenWindowIsClamped() async throws {
    try prepare()
    let requested = boundary.addingTimeInterval(-30 * 86400)
    let available = boundary.addingTimeInterval(-14 * 86400)
    let owner = TandemSyncOwner(accountId: try XCTUnwrap(account.accountId))
    metadata.recordSuccess(sampleCount: 0, importedCount: 0, completedAt: requested, watermark: requested, owner: owner)
    await source.setResult(.success(.init(samples: [], effectiveMinDate: available, effectiveMaxDate: boundary, dataSourceMode: .tandemSource)))
    let result = await coordinator.run(reason: .manual)
    XCTAssertEqual(result, .completed)
    guard case .succeeded(let completion) = coordinator.operationState else { return XCTFail("Missing sync summary") }
    XCTAssertTrue(completion.notice?.contains("PumpSync’s 14-day import window") == true)
    XCTAssertEqual(metadata.metadata.syncWatermark, boundary.addingTimeInterval(-86400))
  }

  func testStartFromNowCannotRewindBeforeChosenStartOnTheNextSync() async throws {
    try prepare()
    metadata.setInitialImportRange(.startFromNow)
    await source.setResult(.success(.init(samples: [], effectiveMinDate: boundary, effectiveMaxDate: boundary, dataSourceMode: .tandemSource)))
    let result = await coordinator.run(reason: .manual)
    XCTAssertEqual(result, .completed)
    XCTAssertEqual(metadata.metadata.syncWatermark, boundary)
  }

  func testMissingValidationHealthAndExpiredLeaseCannotStartDownload() async throws {
    try prepare(validated: false)
    let withoutAccount = await coordinator.run(reason: .manual)
    XCTAssertEqual(withoutAccount, .blocked(.credentials))
    try account.saveValidated(credentials)
    health.hasAnyWritePermission = false
    let noHealth = await coordinator.run(reason: .manual)
    XCTAssertEqual(noHealth, .blocked(.healthPermission))
    let bareBackground = await coordinator.run(reason: .background)
    XCTAssertEqual(bareBackground, .deferred(.executionLeaseExpired))
    let expired = await coordinator.run(reason: .background, lease: SyncExecutionLease(kind: .background, deadline: .distantPast))
    XCTAssertEqual(expired, .deferred(.executionLeaseExpired))
    let calls = await source.callCount
    XCTAssertEqual(calls, 0)
    XCTAssertNil(metadata.metadata.syncWatermark)
  }

  func testPartialHealthPermissionsAllowLaterBackfill() async throws {
    try prepare(samples: [sample("a"), sample("b")])
    health.droppedExternalIds = ["b"]
    let partial = await coordinator.run(reason: .manual)
    XCTAssertEqual(partial, .completed)
    XCTAssertEqual(metadata.metadata.lastPermissionSkippedCount, 1)
    XCTAssertEqual(try ledger.filterUnseen([sample("a"), sample("b")]), [sample("b")])
    health.droppedExternalIds = []
    let retry = await coordinator.run(reason: .manual)
    XCTAssertEqual(retry, .completed)
    XCTAssertEqual(health.savedSamples, [sample("b")])
    XCTAssertEqual(metadata.metadata.lastPermissionSkippedCount, 0)
  }

  func testProviderCredentialRejectionIsOnlyErrorThatInvalidatesAccount() async throws {
    try prepare()
    for error in [DirectTandemError.unavailable, .rateLimited, .accessDenied, .invalidResponse] {
      await source.setResult(.failure(error))
      let result = await coordinator.run(reason: .manual)
      XCTAssertEqual(result, .failed)
      XCTAssertTrue(account.hasValidatedCredentials)
      XCTAssertNil(metadata.metadata.syncWatermark)
    }
    await source.setResult(.failure(.credentialsRejected))
    let result = await coordinator.run(reason: .manual)
    XCTAssertEqual(result, .failed)
    XCTAssertFalse(account.hasValidatedCredentials)
  }

  func testDirectImportRejectsSyntheticBatchBeforeSubmittingToHealth() async throws {
    try prepare(samples: [sample("fixture")], mode: .syntheticDemo)
    let result = await coordinator.run(reason: .manual)
    XCTAssertEqual(result, .failed)
    XCTAssertTrue(health.savedSamples.isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertEqual(try ledger.filterUnseen([sample("fixture")]).count, 1)
  }

  func testReplacedCredentialRevisionDiscardsLateDataAndLateCredentialRejection() async throws {
    try prepare(samples: [sample("stale")], held: true)
    let task = Task { await coordinator.run(reason: .manual) }
    try await until { await self.source.callCount > 0 }
    try account.saveValidated(.init(username: "replacement", password: "fixture", region: "us"))
    await source.release()
    let result = await task.value
    XCTAssertEqual(result, .contextReplaced)
    XCTAssertTrue(health.savedSamples.isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)

    source = DirectImportTestSource(.failure(.credentialsRejected), held: true)
    coordinator = makeCoordinator(health: health, ledger: ledger)
    let lateRejection = Task { await coordinator.run(reason: .manual) }
    try await until { await self.source.callCount > 0 }
    try account.saveValidated(credentials)
    await source.release()
    let rejected = await lateRejection.value
    XCTAssertEqual(rejected, .contextReplaced)
    XCTAssertTrue(account.hasValidatedCredentials)
  }

  func testCoalescedWaitersKeepDownloadAliveAfterInitialForegroundLeaseEnds() async throws {
    try prepare(samples: [sample("coalesced")], held: true)
    let first = Task { await coordinator.run(reason: .manual) }
    try await until { await self.source.callCount > 0 }
    let background = Task { await coordinator.run(reason: .background, lease: grant()) }
    await Task.yield()
    coordinator.setForegroundActive(false)
    await source.release()
    let foregroundResult = await first.value
    let backgroundResult = await background.value
    XCTAssertEqual(foregroundResult, .canceled)
    XCTAssertEqual(backgroundResult, .completed)
    let calls = await source.callCount
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(metadata.metadata.lastImportedCount, 1)
  }

  func testRealAdapterChecksExecutionLeaseAtFinalHealthSubmission() async throws {
    try prepare(samples: [sample("late")])
    let lease = grant()
    let recording = SubmissionRecordingHealthPersistence()
    var checks = 0
    let adapter = HealthKitService(currentContext: {
      checks += 1
      if checks == 2 { lease.revoke() }
      return self.account.currentImportSnapshot
    }, persistence: recording)
    coordinator = makeCoordinator(health: adapter, ledger: ledger)
    let result = await coordinator.run(reason: .background, lease: lease)
    XCTAssertEqual(result, .deferred(.executionLeaseExpired))
    XCTAssertEqual(checks, 2)
    XCTAssertTrue(recording.saved.isEmpty)
    XCTAssertNil(metadata.metadata.syncWatermark)
  }

  func testCancellationAfterHealthSubmissionLedgersConfirmedWritesWithoutAdvancingHistory() async throws {
    try prepare(samples: [sample("submitted")])
    health.suspendsSave = true
    let running = Task { await coordinator.run(reason: .manual) }
    try await until { !self.health.savedSamples.isEmpty }
    coordinator.setForegroundActive(false)
    health.resumeSave()
    let result = await running.value
    XCTAssertEqual(result, .canceled)
    XCTAssertTrue(try ledger.filterUnseen([sample("submitted")]).isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertEqual(coordinator.attemptStore.history.first?.importCheckpoint, .ledgerCommitCompleted)
  }

  func testLedgerFailureAfterHealthSaveDoesNotPublishSuccess() async throws {
    try prepare(samples: [sample("confirmed")])
    let failing = FailingSyncSampleLedger()
    coordinator = makeCoordinator(health: health, ledger: failing)
    let result = await coordinator.run(reason: .manual)
    XCTAssertEqual(result, .failed)
    XCTAssertEqual(failing.commitCount, 1)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertEqual(coordinator.attemptStore.history.first?.importCheckpoint, .ledgerCommitStarted)
  }
}
