import XCTest
@testable import PumpSync

@MainActor
private final class FakeHealthKitService: SyncHealthWriting {
  var hasAnyWritePermission: Bool
  var saveError: Error?
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

  func save(samples: [SampleDTO]) async throws -> [SampleDTO] {
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

private struct StubTandemSyncResponse: Encodable {
  let samples: [SampleDTO]
  let effectiveMinDate: Date
  let effectiveMaxDate: Date
}

private final class LockIsolated<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Value

  init(_ value: Value) {
    storedValue = value
  }

  var value: Value {
    lock.withLock { storedValue }
  }

  func withValue<Result>(_ operation: (inout Value) -> Result) -> Result {
    lock.withLock { operation(&storedValue) }
  }
}

@MainActor
final class SyncCoordinatorTests: XCTestCase {
  override func tearDown() {
    URLProtocolStub.requestHandler = nil
    super.tearDown()
  }

  func testManualSyncPublishesEveryOperationPhaseBeforeSuccess() async throws {
    let requestStarted = expectation(description: "sync request started")
    let saveStarted = expectation(description: "HealthKit save started")
    let allowResponse = DispatchSemaphore(value: 0)
    let fakeHealthKit = FakeHealthKitService()
    fakeHealthKit.suspendsSave = true
    fakeHealthKit.saveStarted = { saveStarted.fulfill() }
    let responseHandler = syncResponseHandler(
      samples: [sample(externalId: "sample-1")],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    URLProtocolStub.requestHandler = { request in
      requestStarted.fulfill()
      allowResponse.wait()
      return try responseHandler(request)
    }
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit
    )

    coordinator.startManualSync()

    guard case .running(let preparing) = coordinator.operationState else {
      return XCTFail("expected preparing state")
    }
    XCTAssertEqual(preparing.phase, .preparing)
    XCTAssertEqual(preparing.trigger, .manual)

    await fulfillment(of: [requestStarted], timeout: 2)
    guard case .running(let downloading) = coordinator.operationState else {
      return XCTFail("expected downloading state")
    }
    XCTAssertEqual(downloading.phase, .downloading)

    allowResponse.signal()
    await fulfillment(of: [saveStarted], timeout: 2)
    guard case .running(let updatingHealth) = coordinator.operationState else {
      return XCTFail("expected updating Health state")
    }
    XCTAssertEqual(updatingHealth.phase, .updatingHealth)

    fakeHealthKit.resumeSave()
    await waitUntil { !coordinator.isSyncing }
    guard case .succeeded(let completion) = coordinator.operationState else {
      return XCTFail("expected successful completion")
    }
    XCTAssertEqual(completion.message, "Imported 1 new samples.")
  }

  func testDuplicateManualStartsIssueOnlyOneRequest() async throws {
    let requestStarted = expectation(description: "sync request started")
    let allowResponse = DispatchSemaphore(value: 0)
    let requestCount = LockIsolated(0)
    let responseHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    URLProtocolStub.requestHandler = { request in
      requestCount.withValue { $0 += 1 }
      requestStarted.fulfill()
      allowResponse.wait()
      return try responseHandler(request)
    }
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore()
    )

    coordinator.startManualSync()
    coordinator.startManualSync()
    await fulfillment(of: [requestStarted], timeout: 2)
    XCTAssertEqual(requestCount.value, 1)

    allowResponse.signal()
    await waitUntil { !coordinator.isSyncing }
  }

  func testTransientFailureOffersRetryAndRetryCanSucceed() async throws {
    let attempt = LockIsolated(0)
    let responseHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    URLProtocolStub.requestHandler = { request in
      let currentAttempt = attempt.withValue { value in
        value += 1
        return value
      }
      if currentAttempt == 1 {
        throw URLError(.networkConnectionLost)
      }
      return try responseHandler(request)
    }
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore()
    )

    await coordinator.sync(reason: .manual)
    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(message: "Sync could not be completed. Try again.", recovery: .retry))
    )

    coordinator.retry()
    await waitUntil { !coordinator.isSyncing }
    guard case .succeeded = coordinator.operationState else {
      return XCTFail("expected retry to replace the failure with success")
    }
    XCTAssertEqual(attempt.value, 2)
  }

  func testBlockedPrerequisiteOffersSettingsRecovery() async throws {
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: makeCredentialStore()
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(message: "Save your pump account credentials before syncing.", recovery: .openSettings))
    )
  }

  func testRateLimitDoesNotOfferImmediateRetry() async throws {
    URLProtocolStub.requestHandler = errorResponseHandler(
      statusCode: 429,
      code: "rate_limit_exceeded",
      message: "Rate limit exceeded for 'sync-tandem'."
    )
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore()
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(message: "Sync limit reached. Wait a while before trying again.", recovery: .waitAndRetry))
    )
  }

  func testBackgroundSuccessReturnsToIdleWithoutPublishingCompletion() async throws {
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore()
    )

    await coordinator.sync(reason: .background)

    XCTAssertEqual(coordinator.operationState, .idle)
  }

  func testHealthAuthorizationFailureOffersSettingsRecovery() async throws {
    let fakeHealthKit = FakeHealthKitService()
    fakeHealthKit.saveError = HealthKitError.authorizationDenied
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [sample(externalId: "sample-1")],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(message: "Enable Apple Health write access before syncing.", recovery: .openSettings))
    )
  }

  func testDismissResultReturnsToIdleButCannotDismissRunningOperation() async throws {
    let requestStarted = expectation(description: "sync request started")
    let allowResponse = DispatchSemaphore(value: 0)
    let responseHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    URLProtocolStub.requestHandler = { request in
      requestStarted.fulfill()
      allowResponse.wait()
      return try responseHandler(request)
    }
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore()
    )

    coordinator.startManualSync()
    await fulfillment(of: [requestStarted], timeout: 2)
    coordinator.dismissResult()
    XCTAssertTrue(coordinator.isSyncing)

    allowResponse.signal()
    await waitUntil { !coordinator.isSyncing }
    coordinator.dismissResult()
    XCTAssertEqual(coordinator.operationState, .idle)
  }

  func testHostedSyncWithNoActiveSubscriptionOffersSubscription() async throws {
    let diagnostics = makeDiagnostics()
    let coordinator = makeCoordinator(
      authService: makeSignedOutAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      diagnostics: diagnostics
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(
        message: "Your PumpSync subscription isn’t active. Subscribe or renew to resume syncing.",
        recovery: .openSubscription
      ))
    )
    XCTAssertFalse(coordinator.isSyncing)
    XCTAssertEqual(diagnostics.entries.first?.title, "Sync blocked")
  }

  func testSelfHostedSyncWithoutConnectionStillOpensSettings() async throws {
    let configuration = BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!)
    configuration.mode = .selfHosted
    let authService = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: URL(string: "https://example.com/api")!, urlSession: .shared, maxRetryCount: 0),
      configurationStore: configuration,
      sessionStore: nil,
      currentEntitlementJWS: {
        XCTFail("Self-hosted recovery must not read StoreKit entitlements")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: StubDeviceSessionProofProvider()
    )
    let coordinator = makeCoordinator(
      authService: authService,
      credentialStore: try makeValidatedCredentialStore()
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(message: "Connect PumpSync before syncing.", recovery: .openSettings))
    )
  }

  func testSyncBlockedWhenCredentialsNotValidated() async {
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: makeCredentialStore()
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, "Save your pump account credentials before syncing.")
  }

  func testSyncBlockedWhenNoHealthWritePermission() async throws {
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: false)
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, "Enable Apple Health write access before syncing.")
    XCTAssertEqual(fakeHealthKit.refreshAuthorizationStatusCallCount, 1, "permission state should still be refreshed even though the sync doesn't proceed")
  }

  func testSuccessfulSyncImportsUnseenSamplesAndRecordsWatermarkFromServerEffectiveMaxDate() async throws {
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    let syncMetadataStore = makeSyncMetadataStore()
    let diagnostics = makeDiagnostics()
    let samples = [sample(externalId: "sample-1"), sample(externalId: "sample-2")]
    let effectiveMinDate = Date(timeIntervalSince1970: 1_000_000)
    let effectiveMaxDate = Date(timeIntervalSince1970: 1_100_000)
    URLProtocolStub.requestHandler = syncResponseHandler(samples: samples, effectiveMinDate: effectiveMinDate, effectiveMaxDate: effectiveMaxDate)

    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit,
      syncMetadataStore: syncMetadataStore,
      diagnostics: diagnostics
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, "Imported 2 new samples.")
    XCTAssertFalse(coordinator.isSyncing)
    XCTAssertEqual(fakeHealthKit.savedSamples.map(\.externalId), ["sample-1", "sample-2"])
    // The next request's minDate watermark must come from the server's
    // reported effective window, minus the overlap, not a client-side
    // Date() — this is the I4 fix.
    XCTAssertEqual(syncMetadataStore.metadata.syncWatermark, effectiveMaxDate.addingTimeInterval(-24 * 60 * 60))
    // lastSuccessfulSyncAt is a separate field driving staleness checks and
    // "last synced" UI display — it must be the real completion time, not
    // the watermark (which is deliberately ~24h earlier). Reusing the
    // watermark here made every sync look immediately stale.
    XCTAssertEqual(syncMetadataStore.metadata.lastSuccessfulSyncAt?.timeIntervalSinceNow ?? -.infinity, 0, accuracy: 5)
    XCTAssertEqual(diagnostics.entries.first?.title, "Sync completed")
  }

  func testSyncDeduplicatesAlreadyImportedSamplesBeforeSavingToHealthKit() async throws {
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    let importedSampleLedger = ImportedSampleLedger(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!
    )
    let alreadyImported = sample(externalId: "already-imported")
    let new = sample(externalId: "new-sample")
    try importedSampleLedger.recordImported([alreadyImported])
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [alreadyImported, new],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )

    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit,
      importedSampleLedger: importedSampleLedger
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(fakeHealthKit.savedSamples.map(\.externalId), ["new-sample"])
  }

  func testAuthenticationFailureDuringSyncClearsSession() async throws {
    let authService = makeSignedInAuthService()
    let syncMetadataStore = makeSyncMetadataStore()
    URLProtocolStub.requestHandler = errorResponseHandler(statusCode: 401, code: "invalid_token", message: "Service token expired.")

    let coordinator = makeCoordinator(
      authService: authService,
      credentialStore: try makeValidatedCredentialStore(),
      syncMetadataStore: syncMetadataStore
    )
    XCTAssertTrue(authService.isSignedIn)

    await coordinator.sync(reason: .manual)

    XCTAssertFalse(authService.isSignedIn, "a 401 from the sync endpoint should clear the now-invalid session")
    XCTAssertEqual(coordinator.lastMessage, "Sync could not be completed. Try again.")
    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(message: "Sync could not be completed. Try again.", recovery: .openSettings))
    )
    XCTAssertNotNil(syncMetadataStore.metadata.lastErrorMessage)
  }

  func testHostedSyncWithExpiredSubscriptionOffersSubscriptionWithoutClearingSession() async throws {
    let authService = makeSignedInAuthService()
    URLProtocolStub.requestHandler = errorResponseHandler(
      statusCode: 401,
      code: "active_subscription_required",
      message: "An active PumpSync subscription is required."
    )
    let coordinator = makeCoordinator(
      authService: authService,
      credentialStore: try makeValidatedCredentialStore()
    )

    await coordinator.sync(reason: .manual)

    XCTAssertTrue(authService.isSignedIn, "an expired subscription must not discard a valid renewable session")
    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(
        message: "Your PumpSync subscription isn’t active. Subscribe or renew to resume syncing.",
        recovery: .openSubscription
      ))
    )
  }

  func testRefreshIfStaleSkipsSyncWhenRecentlySuccessful() async throws {
    let syncMetadataStore = makeSyncMetadataStore()
    syncMetadataStore.recordSuccess(sampleCount: 1, importedCount: 1, completedAt: Date(), watermark: Date())
    let diagnostics = makeDiagnostics()
    // No requestHandler installed: if sync() were reached, the client would
    // fail with badServerResponse instead of silently succeeding, so a
    // non-nil lastMessage here would prove the guard didn't hold.
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      syncMetadataStore: syncMetadataStore,
      diagnostics: diagnostics
    )

    await coordinator.refreshIfStale(reason: .appOpen)

    XCTAssertNil(coordinator.lastMessage)
    XCTAssertEqual(diagnostics.entries.first?.title, "Sync skipped")
    let freshnessEntry = diagnostics.entries.first { $0.title == "Background sync freshness evaluated" }
    XCTAssertTrue(freshnessEntry?.message?.contains("reason=appOpen decision=skip") == true)
    XCTAssertTrue(freshnessEntry?.message?.contains("targetSeconds=14400") == true)
  }

  func testBackgroundSyncReportsFailureWhenConnectionRecoveryFails() async throws {
    let coordinator = makeCoordinator(
      authService: makeSignedOutAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: FakeHealthKitService(hasAnyWritePermission: true)
    )

    let succeeded = await coordinator.performBackgroundSync()

    XCTAssertFalse(succeeded)
    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(message: "Connect PumpSync before syncing.", recovery: .openSettings))
    )
  }

  func testBackgroundSyncWaitsForConcurrentAppOpenSync() async throws {
    let requestStarted = expectation(description: "sync request started")
    let allowResponse = DispatchSemaphore(value: 0)
    let responseData = try JSONCodec.encoder.encode(StubTandemSyncResponse(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    ))
    URLProtocolStub.requestHandler = { request in
      requestStarted.fulfill()
      allowResponse.wait()
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: FakeHealthKitService(hasAnyWritePermission: true)
    )

    let appOpen = Task { await coordinator.refreshIfStale(reason: .appOpen) }
    await fulfillment(of: [requestStarted], timeout: 1)
    let background = Task { await coordinator.performBackgroundSync() }
    await Task.yield()
    allowResponse.signal()

    let appOpenOutcome = await appOpen.value
    let backgroundSucceeded = await background.value
    XCTAssertEqual(appOpenOutcome, .completed)
    XCTAssertTrue(backgroundSucceeded)
  }

  func testRefreshIfStaleDoesNotImmediatelyReSyncAfterARealSyncCompletes() async throws {
    // Regression test: recording the watermark (~24h before "now") into
    // lastSuccessfulSyncAt instead of the real completion time made every
    // sync look already-stale the instant it finished, forcing an
    // unnecessary re-sync on the very next staleness check.
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    let syncMetadataStore = makeSyncMetadataStore()
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date()
    )
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit,
      syncMetadataStore: syncMetadataStore
    )
    await coordinator.sync(reason: .manual)
    XCTAssertNotNil(syncMetadataStore.metadata.lastSuccessfulSyncAt)

    // A second staleness check right after should not reach the network at
    // all. Removing the handler means a request that does escape the
    // staleness guard fails with .badServerResponse instead of silently
    // succeeding, which would surface as a changed lastMessage below.
    URLProtocolStub.requestHandler = nil
    let messageBeforeSecondCheck = coordinator.lastMessage

    await coordinator.refreshIfStale(reason: .appOpen)

    XCTAssertEqual(coordinator.lastMessage, messageBeforeSecondCheck, "a sync that just completed should not look stale enough to trigger another one immediately")
  }

  func testRefreshIfStaleSyncsWhenNoPriorSuccessfulSync() async throws {
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit
    )

    await coordinator.refreshIfStale(reason: .appOpen)

    XCTAssertEqual(coordinator.lastMessage, "No new pump samples were returned.")
  }

  func testAppOpenSyncDoesNotRepeatFailedEnrollmentButManualSyncCanRetry() async {
    var entitlementCalls = 0
    var enrollmentCalls = 0
    let authService = AuthService(
      apiClient: PumpSyncAPIClient(
        baseURL: URL(string: "https://example.com/api")!,
        urlSession: URLProtocolStub.makeSession(),
        maxRetryCount: 0
      ),
      configurationStore: BackendConfigurationStore(
        defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!
      ),
      sessionStore: nil,
      currentEntitlementJWS: {
        entitlementCalls += 1
        return "signed-transaction"
      },
      createSubscriptionSession: { _ in
        enrollmentCalls += 1
        throw APIClientError.httpStatus(
          401,
          code: "device_proof_rejected",
          message: "The device proof was rejected."
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: RecoveringDeviceSessionProofProvider()
    )
    let coordinator = makeCoordinator(
      authService: authService,
      credentialStore: makeCredentialStore()
    )

    await authService.recoverSessionIfNeeded()
    await coordinator.refreshIfStale(reason: .appOpen)

    XCTAssertEqual(entitlementCalls, 1)
    XCTAssertEqual(enrollmentCalls, 1)

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(entitlementCalls, 2)
    XCTAssertEqual(enrollmentCalls, 2)
  }

  func testSamplesDroppedByHealthKitAreNotMarkedImported() async throws {
    // A sample skipped by save() (missing per-type permission or unknown
    // type) must stay out of the dedupe ledger so a later permission grant
    // can still import it from the watermark-overlap re-fetch. Ledgering it
    // would lose it permanently — the backend retains nothing to replay.
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    fakeHealthKit.droppedExternalIds = ["carb-1"]
    let importedSampleLedger = ImportedSampleLedger(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!
    )
    let written = sample(externalId: "bolus-1")
    let dropped = sample(externalId: "carb-1")
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [written, dropped],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )

    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit,
      importedSampleLedger: importedSampleLedger
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, "Imported 1 new samples.")
    XCTAssertEqual(try importedSampleLedger.filterUnseen([written]).count, 0, "the written sample should be ledgered")
    XCTAssertEqual(try importedSampleLedger.filterUnseen([dropped]).count, 1, "the dropped sample must remain importable")
  }

  func testTandemCredentialRejectionInvalidatesValidationAndSurfacesBackendMessage() async throws {
    let authService = makeSignedInAuthService()
    let credentialStore = try makeValidatedCredentialStore()
    let backendMessage = "Tandem Source did not accept the supplied pump account credentials. Re-save your Tandem account credentials in PumpSync."
    URLProtocolStub.requestHandler = errorResponseHandler(statusCode: 424, code: "tandem_authentication_failed", message: backendMessage)

    let coordinator = makeCoordinator(authService: authService, credentialStore: credentialStore)
    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, backendMessage, "the backend's remediation guidance is user-facing and must reach the user")
    XCTAssertFalse(credentialStore.hasValidatedCredentials, "a Tandem rejection means the stored credentials need re-validation")
    XCTAssertTrue(authService.isSignedIn, "a Tandem credential failure is not a PumpSync session failure")
  }

  func testRateLimitedSyncShowsWaitMessage() async throws {
    URLProtocolStub.requestHandler = errorResponseHandler(statusCode: 429, code: "rate_limit_exceeded", message: "Rate limit exceeded for 'sync-tandem'.")

    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore()
    )
    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, "Sync limit reached. Wait a while before trying again.")
  }

  func testLookbackClampSurfacesDataGapNotice() async throws {
    // The backend clamps the requested window to Tandem's ~14-day lookback
    // and reports the effective start; data before it is unrecoverable, so
    // the sync must not report an unqualified success.
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date().addingTimeInterval(-24 * 60 * 60),
      effectiveMaxDate: Date()
    )

    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: fakeHealthKit
    )
    await coordinator.sync(reason: .manual)

    XCTAssertTrue(
      coordinator.lastMessage?.contains("no longer available") == true,
      "expected a data-gap notice, got: \(coordinator.lastMessage ?? "nil")"
    )
  }

  func testSyncRequestCarriesDeviceTimeZone() async throws {
    // Tandem timestamps are pump-local wall-clock values; without the
    // device's zone the backend anchors them to UTC and every sample lands
    // hours off in Apple Health.
    let capturedBody = CapturedBody()
    URLProtocolStub.requestHandler = { request in
      capturedBody.store(Self.bodyData(from: request))
      let body = StubTandemSyncResponse(samples: [], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000))
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(body)
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
      return (response, data)
    }

    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore()
    )
    await coordinator.sync(reason: .manual)

    let body = try XCTUnwrap(capturedBody.value)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(json["timeZoneIdentifier"] as? String, TimeZone.current.identifier)
  }

  // MARK: - Fixtures

  private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () -> Bool
  ) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
      await Task.yield()
    }
    XCTAssertTrue(condition(), "condition was not met before timeout")
  }

  private final class CapturedBody: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    func store(_ data: Data?) {
      lock.lock()
      defer { lock.unlock() }
      self.data = data
    }

    var value: Data? {
      lock.lock()
      defer { lock.unlock() }
      return data
    }
  }

  private nonisolated static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
      return body
    }

    guard let stream = request.httpBodyStream else {
      return nil
    }

    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
      let read = stream.read(buffer, maxLength: bufferSize)
      guard read > 0 else {
        break
      }
      data.append(buffer, count: read)
    }

    return data
  }

  private func makeCoordinator(
    authService: AuthService,
    credentialStore: TandemCredentialStore,
    healthKitService: SyncHealthWriting = FakeHealthKitService(),
    importedSampleLedger: ImportedSampleLedger? = nil,
    syncMetadataStore: SyncMetadataStore? = nil,
    diagnostics: DiagnosticsLogStore? = nil
  ) -> SyncCoordinator {
    SyncCoordinator(
      apiClient: PumpSyncAPIClient(baseURL: URL(string: "https://example.com/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0),
      authService: authService,
      credentialStore: credentialStore,
      healthKitService: healthKitService,
      importedSampleLedger: importedSampleLedger ?? ImportedSampleLedger(
        keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
        defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!
      ),
      syncMetadataStore: syncMetadataStore ?? makeSyncMetadataStore(),
      diagnostics: diagnostics
    )
  }

  private func makeSignedInAuthService() -> AuthService {
    let service = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: URL(string: "https://example.com/api")!, urlSession: .shared, maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!),
      sessionStore: nil,
      currentEntitlementJWS: {
        XCTFail("StoreKit should not be reached when a session is already present")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("Backend session creation should not be reached when a session is already present")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        XCTFail("Backend session creation should not be reached when a session is already present")
        throw APIClientError.invalidResponse
      },
      proofProvider: StubDeviceSessionProofProvider()
    )
    service.applyScreenshotSession(serviceMode: "hosted")
    return service
  }

  private func makeSignedOutAuthService() -> AuthService {
    AuthService(
      apiClient: PumpSyncAPIClient(baseURL: URL(string: "https://example.com/api")!, urlSession: .shared, maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!),
      sessionStore: nil,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: StubDeviceSessionProofProvider()
    )
  }

  private func makeCredentialStore() -> TandemCredentialStore {
    TandemCredentialStore(keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"))
  }

  private func makeValidatedCredentialStore() throws -> TandemCredentialStore {
    let store = makeCredentialStore()
    try store.saveValidated(TandemCredentials(username: "demo@pumpsync.app", password: "hunter2", region: "us"))
    return store
  }

  private func makeSyncMetadataStore() -> SyncMetadataStore {
    SyncMetadataStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!)
  }

  private final class StubDeviceSessionProofProvider: DeviceSessionProofProviding {
    func hostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String,
      signedTransactionInfo: String
    ) async throws -> HostedDeviceEnrollment {
      throw APIClientError.invalidResponse
    }

    func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool { false }
    func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool { false }
    func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardRegisteredHostedKey() throws -> Bool { false }
    func releaseHostedProofOperation(requestId: String) -> Bool { false }

    func selfHostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String
    ) throws -> SelfHostedDeviceEnrollment {
      throw APIClientError.invalidResponse
    }

    func refreshRequest(
      session: BackendSessionResponse,
      installationId: String,
      mode: BackendAccessMode
    ) async throws -> SessionRefreshRequest {
      throw APIClientError.invalidResponse
    }
  }

  private final class RecoveringDeviceSessionProofProvider: DeviceSessionProofProviding {
    func hostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String,
      signedTransactionInfo: String
    ) async throws -> HostedDeviceEnrollment {
      HostedDeviceEnrollment(
        requestId: UUID().uuidString,
        issuedAt: Date(),
        challengeToken: challenge.challengeToken,
        keyId: "key",
        proofKind: "attestation",
        proof: "proof"
      )
    }

    func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool { true }
    func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool { true }
    func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardRegisteredHostedKey() throws -> Bool { false }
    func releaseHostedProofOperation(requestId: String) -> Bool { false }

    func selfHostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String
    ) throws -> SelfHostedDeviceEnrollment {
      throw APIClientError.invalidResponse
    }

    func refreshRequest(
      session: BackendSessionResponse,
      installationId: String,
      mode: BackendAccessMode
    ) async throws -> SessionRefreshRequest {
      throw APIClientError.invalidResponse
    }
  }

  private func makeDiagnostics() -> DiagnosticsLogStore {
    DiagnosticsLogStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!)
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

  private func syncResponseHandler(
    samples: [SampleDTO],
    effectiveMinDate: Date,
    effectiveMaxDate: Date
  ) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
    { request in
      let body = StubTandemSyncResponse(samples: samples, effectiveMinDate: effectiveMinDate, effectiveMaxDate: effectiveMaxDate)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let data = try encoder.encode(body)
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
      return (response, data)
    }
  }

  private func errorResponseHandler(statusCode: Int, code: String, message: String) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
    { request in
      let data = try JSONEncoder().encode(["code": code, "message": message])
      let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
      return (response, data)
    }
  }
}
