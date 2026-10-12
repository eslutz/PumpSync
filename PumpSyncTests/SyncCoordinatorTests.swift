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

private final class FailingSyncSampleLedger: SyncSampleLedger {
  private(set) var commitCount = 0
  func filterUnseen(_ samples: [SampleDTO]) throws -> [SampleDTO] { samples }
  func recordImported(_ samples: [SampleDTO], importedAt: Date) throws {
    commitCount += 1
    throw KeychainStoreError.invalidData
  }
}

private struct StubTandemSyncResponse: Encodable {
  var dataSourceMode = "tandemSource"
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
  func testLegacyUnboundCursorResetsBeforeDownloadEvenWithValidatedAccount() async throws {
    let metadata = makeSyncMetadataStore()
    metadata.setInitialImportRange(.pastTwoDays)
    metadata.applyScreenshotMetadata(.init(lastAttemptAt: nil, lastSuccessfulSyncAt: Date(), lastSampleCount: 9, lastImportedCount: 8, lastErrorMessage: nil, initialImportRange: .pastTwoDays, syncWatermark: Date(timeIntervalSince1970: 100)))
    let health = FakeHealthKitService(hasAnyWritePermission: false)
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    let result = await coordinator.run(reason: .manual)
    XCTAssertEqual(result, .blocked(.healthPermission))
    XCTAssertNil(metadata.metadata.syncWatermark)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertEqual(metadata.metadata.lastSampleCount, 0)
    XCTAssertEqual(metadata.metadata.lastImportedCount, 0)
    XCTAssertEqual(metadata.metadata.initialImportRange, .pastTwoDays)
    XCTAssertTrue(health.savedSamples.isEmpty)
  }

  func testAccountReplacementResetsCursorBeforeFreshnessAndPreservesLedger() async throws {
    let credentials = try makeValidatedCredentialStore()
    let auth = makeSignedInAuthService()
    let metadata = makeSyncMetadataStore()
    metadata.setInitialImportRange(.pastTwoDays)
    let health = FakeHealthKitService()
    let ledger = ImportedSampleLedger(keychain: SecureKeychainStore(service: "CursorAccount.\(UUID().uuidString)"), defaults: UserDefaults(suiteName: "CursorAccount.\(UUID().uuidString)")!)
    let confirmed = sample(externalId: "preserved-ledger")
    let minima = LockIsolated<[Date]>([])
    let response = syncResponseHandler(samples: [confirmed], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(from: request))) as? [String: Any])
      let minimum = try XCTUnwrap(ISO8601DateFormatter().date(from: XCTUnwrap(body["minDate"] as? String)))
      minima.withValue { $0.append(minimum) }
      return try response(request)
    }
    let coordinator = makeCoordinator(authService: auth, credentialStore: credentials, healthKitService: health, importedSampleLedger: ledger, syncMetadataStore: metadata)
    let first = await coordinator.run(reason: .manual)
    XCTAssertEqual(first, .completed)
    try credentials.saveValidated(.init(username: "replacement@example.com", password: "two", region: "us"))
    let replacement = await coordinator.refreshIfStale(reason: .appOpen)
    XCTAssertEqual(replacement, .completed)
    XCTAssertEqual(minima.value.count, 2)
    XCTAssertEqual(minima.value.last, InitialImportRange.pastTwoDays.minimumDate(relativeTo: Date()))
    XCTAssertTrue(health.savedSamples.isEmpty, "Existing identifiers must still deduplicate after changing the cursor owner")
    XCTAssertTrue(try ledger.filterUnseen([confirmed]).isEmpty)
  }

  override func tearDown() {
    URLProtocolStub.requestHandler = nil
    super.tearDown()
  }

  func testSameAccountRevalidationPasswordChangeAndAuthReplacementPreserveCursor() async throws {
    let credentials = try makeValidatedCredentialStore()
    let auth = makeSignedInAuthService()
    let metadata = makeSyncMetadataStore()
    let health = FakeHealthKitService()
    let expectedWatermark = Date(timeIntervalSince1970: 1_100_000).addingTimeInterval(-24 * 60 * 60)
    let minima = LockIsolated<[Date]>([])
    let response = syncResponseHandler(samples: [sample(externalId: "repeat-record")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000))
    URLProtocolStub.requestHandler = { request in
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(Self.bodyData(from: request))) as? [String: Any])
      let minimum = try XCTUnwrap(ISO8601DateFormatter().date(from: XCTUnwrap(body["minDate"] as? String)))
      minima.withValue { $0.append(minimum) }
      return try response(request)
    }
    let coordinator = makeCoordinator(authService: auth, credentialStore: credentials, healthKitService: health, syncMetadataStore: metadata)
    let first = await coordinator.run(reason: .manual)
    XCTAssertEqual(first, .completed)
    let owner = metadata.metadata.owner
    for transition in ["refresh", "reenroll", "revalidate", "password"] {
      let source = try XCTUnwrap(auth.authenticatedConnection)
      let replacement = BackendSessionResponse(accessToken: "fixture-\(transition)", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "family-\(transition)", refreshToken: "fixture-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
      if transition == "refresh" { try auth.installSession(replacement, installation: .verifiedRefresh(source: source)) }
      if transition == "reenroll" { try auth.installSession(replacement, installation: .enrollment) }
      if transition == "revalidate" {
        let successfulHandler = URLProtocolStub.requestHandler
        URLProtocolStub.requestHandler = errorResponseHandler(statusCode: 424, code: "tandem_authentication_failed", message: "Revalidate the account.")
        let rejected = await coordinator.run(reason: .manual)
        XCTAssertEqual(rejected, .failed)
        XCTAssertFalse(credentials.hasValidatedCredentials)
        XCTAssertEqual(metadata.metadata.owner, owner)
        XCTAssertEqual(metadata.metadata.syncWatermark, expectedWatermark)
        URLProtocolStub.requestHandler = successfulHandler
      }
      if transition == "revalidate" || transition == "password" {
        let prior = try XCTUnwrap(credentials.load())
        try credentials.saveValidated(.init(username: prior.username, password: transition == "password" ? "changed" : prior.password, region: prior.region))
      }
      let result = await coordinator.run(reason: .manual)
      XCTAssertEqual(result, .completed, transition)
      XCTAssertEqual(metadata.metadata.syncWatermark, expectedWatermark, transition)
      XCTAssertEqual(metadata.metadata.owner, owner, transition)
      XCTAssertEqual(minima.value.last, expectedWatermark, transition)
      XCTAssertTrue(health.savedSamples.isEmpty, "Repeated imports must retain deduplication across \(transition)")
    }
  }

  func testBackendReplacementClearsSuccessDisplayWithoutTouchingPreferences() async throws {
    let config = BackendConfigurationStore(defaults: UserDefaults(suiteName: "CursorBackend.\(UUID().uuidString)")!)
    let auth = makeSignedInAuthService(configuration: config)
    let credentials = try makeValidatedCredentialStore()
    let metadata = makeSyncMetadataStore()
    metadata.setInitialImportRange(.pastTwoWeeks)
    let health = FakeHealthKitService()
    URLProtocolStub.requestHandler = syncResponseHandler(samples: [], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    let coordinator = makeCoordinator(authService: auth, credentialStore: credentials, healthKitService: health, syncMetadataStore: metadata)
    let first = await coordinator.run(reason: .manual)
    XCTAssertEqual(first, .completed)
    config.mode = .selfHosted
    config.selfHostedBaseURLString = "https://replacement.example/api/"
    for _ in 0..<10 { await Task.yield() }
    XCTAssertNil(metadata.metadata.syncWatermark)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertEqual(metadata.metadata.cursorResetReason, .backendChanged)
    XCTAssertEqual(metadata.metadata.initialImportRange, .pastTwoWeeks)
    XCTAssertEqual(metadata.metadata.owner?.accountId, credentials.accountId)
    XCTAssertEqual(metadata.metadata.owner?.backendIdentity, "https://replacement.example/api")
    XCTAssertNil(coordinator.lastMessage)
  }

  func testCanceledSubmittedSaveStillLedgersConfirmedWritesWithoutSuccess() async throws {
    let started = expectation(description: "Health submission")
    let health = FakeHealthKitService()
    health.suspendsSave = true
    health.saveStarted = { started.fulfill() }
    let ledger = ImportedSampleLedger(keychain: SecureKeychainStore(service: "CanceledSave.\(UUID().uuidString)"), defaults: UserDefaults(suiteName: "CanceledSave.\(UUID().uuidString)")!)
    let metadata = makeSyncMetadataStore()
    let confirmed = sample(externalId: "confirmed-after-cancel")
    URLProtocolStub.requestHandler = syncResponseHandler(samples: [confirmed], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore(), healthKitService: health, importedSampleLedger: ledger, syncMetadataStore: metadata)
    let task = Task { await coordinator.run(reason: .manual) }
    await fulfillment(of: [started], timeout: 2)
    task.cancel()
    for _ in 0..<10 { await Task.yield() }
    health.resumeSave()
    let result = await task.value
    XCTAssertEqual(result, .canceled)
    XCTAssertTrue(try ledger.filterUnseen([confirmed]).isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertNil(metadata.metadata.syncWatermark)
  }

  func testLedgerCommitFailureAfterHealthSaveDoesNotPublishSuccess() async throws {
    let health = FakeHealthKitService()
    let ledger = FailingSyncSampleLedger()
    let metadata = makeSyncMetadataStore()
    URLProtocolStub.requestHandler = syncResponseHandler(samples: [sample(externalId: "ledger-failure")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore(), healthKitService: health, importedSampleLedger: ledger, syncMetadataStore: metadata)
    let result = await coordinator.run(reason: .manual)
    XCTAssertEqual(result, .failed)
    XCTAssertEqual(health.savedSamples.count, 1)
    XCTAssertEqual(ledger.commitCount, 1)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertNil(metadata.metadata.syncWatermark)
    XCTAssertNotNil(metadata.metadata.lastErrorMessage)
  }

  func testPreviewActivityDefersManualAndBackgroundWithoutPersistentChanges() async throws {
    let health = FakeHealthKitService()
    let metadata = makeSyncMetadataStore()
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    coordinator.setDemoPreviewActive(true)
    let background = await coordinator.refreshIfStale(reason: .background, lease: grantedBackgroundLease())
    let manual = await coordinator.sync(reason: .manual)
    XCTAssertEqual(background, .skippedPreviewActive)
    XCTAssertFalse(manual)
    XCTAssertNil(metadata.metadata.lastAttemptAt)
    XCTAssertNil(metadata.metadata.lastErrorMessage)
    XCTAssertEqual(coordinator.operationState, .idle)
    XCTAssertTrue(health.savedConcentrations.isEmpty)
    XCTAssertEqual(health.refreshAuthorizationStatusCallCount, 0)
    coordinator.setDemoPreviewActive(false)
    URLProtocolStub.requestHandler = syncResponseHandler(samples: [], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    let resumed = await coordinator.sync(reason: .manual)
    XCTAssertTrue(resumed)
  }

  func testSyntheticAndMissingBatchProvenanceNeverReachWriterOrRealMetadata() async throws {
    for mode in ["syntheticDemo", "unknown", ""] {
      let health = FakeHealthKitService()
      let metadata = makeSyncMetadataStore()
      let before = metadata.metadata
      URLProtocolStub.requestHandler = { request in
        let source = mode.isEmpty ? "" : ",\"dataSourceMode\":\"\(mode)\""
        let data = Data("{\"samples\":[],\"effectiveMinDate\":\"2026-10-01T00:00:00Z\",\"effectiveMaxDate\":\"2026-10-01T01:00:00Z\"\(source)}".utf8)
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
      let result = await coordinator.sync(reason: .manual)
      XCTAssertFalse(result)
      XCTAssertTrue(health.savedConcentrations.isEmpty)
      XCTAssertEqual(metadata.metadata.lastAttemptAt, before.lastAttemptAt)
      XCTAssertEqual(metadata.metadata.lastSuccessfulSyncAt, before.lastSuccessfulSyncAt)
      XCTAssertEqual(metadata.metadata.lastErrorMessage, before.lastErrorMessage)
    }
  }

  func testLateUnauthorizedFailureFromReplacedTokenInSameFamilyDoesNotClearFreshSessionOrMetadata() async throws {
    try await verifyStaleDownloadFailure(change: "sameFamilyToken", status: 401, code: "invalid_token")
  }

  func testLateUnauthorizedFailureDoesNotClearReplacementSessionOrPersistFailure() async throws {
    try await verifyStaleDownloadFailure(change: "session", status: 401, code: "invalid_token")
  }

  func testLateTandemRejectionDoesNotInvalidateReplacementCredentialsOrPersistFailure() async throws {
    try await verifyStaleDownloadFailure(change: "credentials", status: 424, code: "tandem_authentication_failed")
  }

  func testLateTransportFailureAfterConfigurationSwitchDoesNotPersistFailure() async throws {
    try await verifyStaleDownloadFailure(change: "configuration", status: nil, code: "")
  }

  func testSupersededRequestTokenWithSameImportContextRemainsFailedAndPreservesFreshAuth() async throws {
    try await verifyStaleDownloadFailure(change: "sameContextToken", status: 401, code: "invalid_token")
  }

  private func verifyStaleDownloadFailure(change: String, status: Int?, code: String) async throws {
    let started = expectation(description: "old download suspended")
    let allow = DispatchSemaphore(value: 0)
    let config = BackendConfigurationStore(defaults: UserDefaults(suiteName: "LateFailureConfig-\(UUID().uuidString)")!)
    let sessionStore = makeSessionStore()
    let auth = makeReplacingAuthService(configuration: config, newFamily: change == "sameFamilyToken" ? "debug-session-family" : "replacement-family", sessionStore: sessionStore)
    auth.applyScreenshotSession(serviceMode: "hosted")
    let credentials = try makeValidatedCredentialStore()
    let metadata = makeSyncMetadataStore()
    metadata.recordSuccess(sampleCount: 8, importedCount: 7, completedAt: Date(timeIntervalSince1970: 1_000), watermark: Date(timeIntervalSince1970: 900), owner: try historyOwner(credentials, auth: auth))
    let prior = metadata.metadata
    let health = FakeHealthKitService()
    let failure = status.map { errorResponseHandler(statusCode: $0, code: code, message: "Old request rejected.") }
    URLProtocolStub.requestHandler = { request in
      started.fulfill()
      allow.wait()
      if let failure { return try failure(request) }
      throw URLError(.networkConnectionLost)
    }
    let coordinator = makeCoordinator(authService: auth, credentialStore: credentials, healthKitService: health, syncMetadataStore: metadata)
    let task = Task { await coordinator.run(reason: .manual) }
    await fulfillment(of: [started], timeout: 2)
    if change == "session" || change == "sameFamilyToken" { let restored = await auth.recoverHostedSubscriptionAfterAccessDenied(); XCTAssertTrue(restored) }
    if change == "sameContextToken" {
      let source = try XCTUnwrap(auth.authenticatedConnection)
      let originalContext = auth.currentImportSnapshot(credentialRevision: credentials.revision)
      try auth.installSession(.init(accessToken: "replacement-token", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: source.session.sessionFamilyId, refreshToken: "replacement-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture), installation: .verifiedRefresh(source: source))
      XCTAssertEqual(auth.currentImportSnapshot(credentialRevision: credentials.revision), originalContext)
    }
    if change == "credentials" { try credentials.saveValidated(TandemCredentials(username: "replacement@example.com", password: "new", region: "us")) }
    if change == "configuration" { config.mode = .selfHosted; config.selfHostedBaseURLString = "https://replacement.example/api" }
    let expectedSession = auth.session
    let expectedCredentialRevision = credentials.revision
    let expectedCredentials = try credentials.load()
    allow.signal()
    let result = await task.value
    XCTAssertEqual(result, change == "sameContextToken" ? .failed : .contextReplaced)
    XCTAssertEqual(auth.session, expectedSession)
    if change == "session" || change == "sameFamilyToken" || change == "sameContextToken" { XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "replacement-token") }
    XCTAssertTrue(credentials.hasValidatedCredentials)
    XCTAssertEqual(credentials.revision, expectedCredentialRevision)
    XCTAssertEqual(try credentials.load(), expectedCredentials)
    if change == "credentials" || change == "configuration" {
      XCTAssertNil(metadata.metadata.syncWatermark)
      XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
      XCTAssertEqual(metadata.metadata.cursorResetReason, change == "credentials" ? .accountChanged : .backendChanged)
    } else {
      XCTAssertEqual(metadata.metadata, prior)
    }
    XCTAssertTrue(health.savedConcentrations.isEmpty)
    XCTAssertEqual(coordinator.lastMessage, "Your connection or pump credentials changed. Start a new sync.")
  }

  func testExpiredSessionRotatingFamilyRefreshContinuesOriginalOperation() async throws {
    try await verifyExpiredSessionRecovery(reenroll: false, rotatesFamily: true)
  }

  func testExpiredSessionNewFamilyReenrollmentCompletesOneFreshOwnedImport() async throws {
    try await verifyExpiredSessionRecovery(reenroll: true)
  }

  func testExpiredSessionSameFamilyRefreshContinuesOriginalOperation() async throws {
    try await verifyExpiredSessionRecovery(reenroll: false)
  }

  private func verifyExpiredSessionRecovery(reenroll: Bool, rotatesFamily: Bool = false) async throws {
    let sessionStore = makeSessionStore()
    let expired = BackendSessionResponse(accessToken: "expired", expiresAt: Date().addingTimeInterval(-60), serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "expired-family", refreshToken: "refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
    try sessionStore.save(expired)
    let config = BackendConfigurationStore(defaults: UserDefaults(suiteName: "ExpiredConfig-\(UUID().uuidString)")!)
    let proof = RecoveringDeviceSessionProofProvider()
    proof.acceptsRefresh = true
    let restored = BackendSessionResponse(accessToken: "restored", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: reenroll ? "new-family" : (rotatesFamily ? "rotated-family" : "expired-family"), refreshToken: "refresh-restored", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
    let auth = AuthService(apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0), configurationStore: config, sessionStore: sessionStore,
      currentEntitlementJWS: { "signed-transaction" }, createSubscriptionSession: { _ in restored }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: proof)
    XCTAssertFalse(auth.isSignedIn)
    let refreshData = try JSONCodec.encoder.encode(restored)
    let syncResponse = syncResponseHandler(samples: [sample(externalId: "expired-recovery")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    let rejectedRefresh = errorResponseHandler(statusCode: 401, code: "invalid_token", message: "Refresh rejected.")
    let downloadedTokens = LockIsolated<[String]>([])
    URLProtocolStub.requestHandler = { request in
      if request.url?.path.hasSuffix("/session/refresh") == true {
        if reenroll { return try rejectedRefresh(request) }
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshData)
      }
      downloadedTokens.withValue { $0.append(request.value(forHTTPHeaderField: "Authorization") ?? "") }
      return try syncResponse(request)
    }
    let metadata = makeSyncMetadataStore()
    let health = FakeHealthKitService()
    let coordinator = makeCoordinator(authService: auth, credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    let result = await coordinator.sync(reason: .manual)
    XCTAssertTrue(result)
    XCTAssertEqual(health.savedConcentrations.count, 1)
    XCTAssertEqual(auth.session?.sessionFamilyId, reenroll ? "new-family" : (rotatesFamily ? "rotated-family" : "expired-family"))
    XCTAssertNotNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertEqual(health.savedSamples.map(\.externalId), ["expired-recovery"])
    XCTAssertEqual(downloadedTokens.value, ["Bearer restored"])
  }

  func testSameFamilyEnrollmentDuringDownloadRejectsOriginalOperation() async throws {
    try await verifySessionReplacementDuringDownload(newFamily: "debug-session-family", expectedSuccess: false)
  }

  func testNewSessionFamilyDuringDownloadRejectsBatchWithoutWriterOrMetadata() async throws {
    try await verifySessionReplacementDuringDownload(newFamily: "new-family", expectedSuccess: false)
  }

  private func verifySessionReplacementDuringDownload(newFamily: String, expectedSuccess: Bool) async throws {
    let started = expectation(description: "download suspended")
    let allow = DispatchSemaphore(value: 0)
    let health = FakeHealthKitService()
    let metadata = makeSyncMetadataStore()
    let configuration = BackendConfigurationStore(defaults: UserDefaults(suiteName: "SessionReplacement-\(UUID().uuidString)")!)
    let auth = makeReplacingAuthService(configuration: configuration, newFamily: newFamily)
    auth.applyScreenshotSession(serviceMode: "hosted")
    let response = syncResponseHandler(samples: [sample(externalId: "replacement")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in started.fulfill(); allow.wait(); return try response(request) }
    let coordinator = makeCoordinator(authService: auth, credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    let task = Task { await coordinator.sync(reason: .manual) }
    await fulfillment(of: [started], timeout: 2)
    let replaced = await auth.recoverHostedSubscriptionAfterAccessDenied()
    XCTAssertTrue(replaced)
    allow.signal()
    let result = await task.value
    XCTAssertEqual(result, expectedSuccess)
    XCTAssertEqual(health.savedConcentrations.count, expectedSuccess ? 1 : 0)
    XCTAssertEqual(metadata.metadata.lastSuccessfulSyncAt != nil, expectedSuccess)
    if !expectedSuccess { XCTAssertNil(metadata.metadata.lastAttemptAt); XCTAssertNil(metadata.metadata.lastErrorMessage) }
  }

  func testConfigurationSwitchDuringAuthRecoveryCannotAdoptReplacementBackend() async throws {
    let authStarted = expectation(description: "auth recovery suspended")
    var resume: CheckedContinuation<String, Never>?
    let config = BackendConfigurationStore(defaults: UserDefaults(suiteName: "AuthConfigSwitch-\(UUID().uuidString)")!)
    let health = FakeHealthKitService()
    let auth = AuthService(apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0), configurationStore: config,
      currentEntitlementJWS: { await withCheckedContinuation { resume = $0; authStarted.fulfill() } },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: RecoveringDeviceSessionProofProvider())
    let metadata = makeSyncMetadataStore()
    let coordinator = makeCoordinator(authService: auth, credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    let task = Task { await coordinator.sync(reason: .manual) }
    await fulfillment(of: [authStarted], timeout: 2)
    config.mode = .selfHosted
    config.selfHostedBaseURLString = "https://other.example/api"
    resume?.resume(returning: "signed-transaction")
    let result = await task.value
    XCTAssertFalse(result)
    XCTAssertEqual(coordinator.lastMessage, "Your connection or pump credentials changed. Start a new sync.")
    XCTAssertTrue(health.savedConcentrations.isEmpty)
    XCTAssertNil(metadata.metadata.lastAttemptAt)
  }

  func testContextChangeAfterSubmittedSaveLedgersConfirmedWritesWithoutPublishingSuccess() async throws {
    let started = expectation(description: "save submitted")
    let health = FakeHealthKitService()
    health.suspendsSave = true
    health.saveStarted = { started.fulfill() }
    let config = BackendConfigurationStore(defaults: UserDefaults(suiteName: "SaveContextSwitch-\(UUID().uuidString)")!)
    let metadata = makeSyncMetadataStore()
    let ledger = ImportedSampleLedger(keychain: SecureKeychainStore(service: "SaveContextSwitch.\(UUID().uuidString)"), defaults: UserDefaults(suiteName: "SaveContextLedger-\(UUID().uuidString)")!)
    let confirmed = sample(externalId: "submitted")
    URLProtocolStub.requestHandler = syncResponseHandler(samples: [confirmed], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(configuration: config), credentialStore: try makeValidatedCredentialStore(), healthKitService: health, importedSampleLedger: ledger, syncMetadataStore: metadata)
    let task = Task { await coordinator.sync(reason: .manual) }
    await fulfillment(of: [started], timeout: 2)
    config.mode = .selfHosted
    config.selfHostedBaseURLString = "https://other.example/api"
    health.resumeSave()
    let result = await task.value
    XCTAssertFalse(result)
    XCTAssertTrue(try ledger.filterUnseen([confirmed]).isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertNil(metadata.metadata.syncWatermark)
  }

  private func makeReplacingAuthService(configuration: BackendConfigurationStore, newFamily: String, sessionStore: BackendSessionStore? = nil) -> AuthService {
    AuthService(apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0), configurationStore: configuration, sessionStore: sessionStore,
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in BackendSessionResponse(accessToken: "replacement-token", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: newFamily, refreshToken: "refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture) },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: RecoveringDeviceSessionProofProvider())
  }

  func testConfigurationChangeDuringDownloadRejectsBatchWithoutRealStateMutation() async throws {
    let started = expectation(description: "download suspended")
    let allow = DispatchSemaphore(value: 0)
    let health = FakeHealthKitService()
    let config = BackendConfigurationStore(defaults: UserDefaults(suiteName: "StaleConfig-\(UUID().uuidString)")!)
    let metadata = makeSyncMetadataStore()
    let response = syncResponseHandler(samples: [sample(externalId: "stale-config")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in
      started.fulfill()
      allow.wait()
      return try response(request)
    }
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(configuration: config), credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    let task = Task { await coordinator.sync(reason: .manual) }
    await fulfillment(of: [started], timeout: 2)
    config.mode = .selfHosted
    config.selfHostedBaseURLString = "https://other.example/api"
    allow.signal()
    let result = await task.value
    XCTAssertFalse(result)
    XCTAssertTrue(health.savedConcentrations.isEmpty)
    XCTAssertNil(metadata.metadata.lastAttemptAt)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertNil(metadata.metadata.lastErrorMessage)
  }

  func testCredentialChangeDuringDownloadRejectsBatchWithoutLedgeringOrSuccess() async throws {
    let started = expectation(description: "download suspended")
    let allow = DispatchSemaphore(value: 0)
    let health = FakeHealthKitService()
    let credentials = try makeValidatedCredentialStore()
    let metadata = makeSyncMetadataStore()
    let response = syncResponseHandler(samples: [sample(externalId: "stale")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in
      started.fulfill()
      allow.wait()
      return try response(request)
    }
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: credentials, healthKitService: health, syncMetadataStore: metadata)
    let task = Task { await coordinator.run(reason: .manual) }
    await fulfillment(of: [started], timeout: 2)
    try credentials.delete()
    allow.signal()
    let result = await task.value
    XCTAssertEqual(result, .contextReplaced)
    XCTAssertTrue(health.savedConcentrations.isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
  }

  func testConcentrationIsCapturedForSharedOperationAndNextSyncUsesNewSetting() async throws {
    let requestStarted = expectation(description: "download suspended")
    let allowResponse = DispatchSemaphore(value: 0)
    let health = FakeHealthKitService()
    let response = syncResponseHandler(samples: [sample(externalId: "concentration")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in
      requestStarted.fulfill()
      allowResponse.wait()
      return try response(request)
    }
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore(), healthKitService: health)
    let first = Task { await coordinator.sync(reason: .manual) }
    await fulfillment(of: [requestStarted], timeout: 2)
    health.concentration = .u500
    let shared = Task { await coordinator.sync(reason: .manual) }
    for _ in 0..<10 { await Task.yield() }
    allowResponse.signal()
    let firstResult = await first.value
    let sharedResult = await shared.value
    XCTAssertTrue(firstResult)
    XCTAssertTrue(sharedResult)
    XCTAssertEqual(health.savedConcentrations, [.u100])
    URLProtocolStub.requestHandler = response
    let nextResult = await coordinator.sync(reason: .manual)
    XCTAssertTrue(nextResult)
    XCTAssertEqual(health.savedConcentrations, [.u100, .u500])
  }

  func testAllCancelledWaitersCannotPublishSuccessAfterHealthSaveCompletes() async throws {
    try await verifySharedCancellation(cancelSecond: true)
  }

  func testCancellingOneSyncWaiterPreservesTheOtherCallersWork() async throws {
    try await verifySharedCancellation(cancelSecond: false)
  }

  private func verifySharedCancellation(cancelSecond: Bool) async throws {
    let saveStarted = expectation(description: "save started")
    let health = FakeHealthKitService()
    health.suspendsSave = true
    health.saveStarted = { saveStarted.fulfill() }
    let metadata = makeSyncMetadataStore()
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [sample(externalId: "cancelled-import")],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date()
    )
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: health,
      syncMetadataStore: metadata
    )
    let first = Task { await coordinator.sync(reason: .background, lease: grantedBackgroundLease()) }
    await fulfillment(of: [saveStarted], timeout: 2)
    let second = Task { await coordinator.sync(reason: .appOpen) }
    for _ in 0..<10 { await Task.yield() }
    first.cancel()
    if cancelSecond { second.cancel() }
    for _ in 0..<10 { await Task.yield() }
    health.resumeSave()
    let firstResult = await first.value
    let secondResult = await second.value
    XCTAssertFalse(firstResult)
    XCTAssertEqual(secondResult, !cancelSecond)
    XCTAssertEqual(metadata.metadata.lastSuccessfulSyncAt == nil, cancelSecond)
    XCTAssertFalse(coordinator.isSyncing)
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

    await coordinator.sync(reason: .background, lease: grantedBackgroundLease())

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

  func testDismissingProgressDoesNotStopSyncOrReappearBetweenPhases() async throws {
    let requestStarted = expectation(description: "download started")
    let saveStarted = expectation(description: "save started")
    let allowResponse = DispatchSemaphore(value: 0)
    let health = FakeHealthKitService()
    health.suspendsSave = true
    health.saveStarted = { saveStarted.fulfill() }
    let responseHandler = syncResponseHandler(
      samples: [sample(externalId: "dismissed-notification")],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    URLProtocolStub.requestHandler = { request in
      requestStarted.fulfill()
      allowResponse.wait()
      return try responseHandler(request)
    }
    let metadata = makeSyncMetadataStore()
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: health,
      syncMetadataStore: metadata
    )
    coordinator.startManualSync()
    await fulfillment(of: [requestStarted], timeout: 2)
    coordinator.dismissNotification()
    XCTAssertTrue(coordinator.isNotificationDismissed)
    XCTAssertTrue(coordinator.isSyncing)
    XCTAssertEqual(coordinator.syncPhase, .downloading)
    allowResponse.signal()
    await fulfillment(of: [saveStarted], timeout: 2)
    XCTAssertTrue(coordinator.isNotificationDismissed)
    XCTAssertTrue(coordinator.isSyncing)
    XCTAssertEqual(coordinator.syncPhase, .updatingHealth)
    health.resumeSave()
    await waitUntil { !coordinator.isSyncing }
    guard case .succeeded = coordinator.operationState else {
      return XCTFail("dismissed sync must still complete")
    }
    XCTAssertNotNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertFalse(coordinator.isNotificationDismissed)
    coordinator.dismissNotification()
    guard case .succeeded = coordinator.operationState else {
      return XCTFail("dismissing a result must preserve the operation result")
    }
    XCTAssertTrue(coordinator.isNotificationDismissed)
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
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0),
      configurationStore: configuration,
      sessionStore: nil,
      currentEntitlementJWS: {
        XCTFail("Self-hosted recovery must not read StoreKit entitlements")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: RecoveringDeviceSessionProofProvider()
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

  func testHostedSyncWithInactiveSubscriptionRetainsRenewableSessionAndOffersSubscription() async throws {
    let sessionStore = makeSessionStore()
    try sessionStore.save(renewableHostedSession())
    let authService = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!),
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: StubDeviceSessionProofProvider()
    )
    authService.applyScreenshotSession(serviceMode: "hosted")
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

    XCTAssertTrue(authService.isSignedIn, "a renewable session should survive a subscription lapse")
    XCTAssertTrue(authService.requiresSubscriptionAction)
    XCTAssertNotNil(sessionStore.loadRecoverableSession())
    XCTAssertEqual(
      coordinator.operationState,
      .failed(SyncFailure(
        message: "Your PumpSync subscription isn’t active. Subscribe or renew to resume syncing.",
        recovery: .openSubscription
      ))
    )
  }

  func testBackgroundSyncRetriesAfterServerEntitlementRestorationWithoutStoreKitEnrollment() async throws {
    let syncRequestCount = LockIsolated(0)
    let subscriptionSessionRequestCount = LockIsolated(0)
    let subscriptionRequiredHandler = errorResponseHandler(
      statusCode: 401,
      code: "active_subscription_required",
      message: "An active PumpSync subscription is required."
    )
    let successfulSyncHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    URLProtocolStub.requestHandler = { request in
      let requestCount = syncRequestCount.withValue { value in
        value += 1
        return value
      }
      if requestCount == 1 {
        return try subscriptionRequiredHandler(request)
      }
      return try successfulSyncHandler(request)
    }

    let sessionStore = makeSessionStore()
    try sessionStore.save(renewableHostedSession())
    let authService = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!),
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      syncedCurrentEntitlementJWS: {
        XCTFail("a background retry must not request an interactive StoreKit refresh")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        subscriptionSessionRequestCount.withValue { $0 += 1 }
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: StubDeviceSessionProofProvider()
    )
    let coordinator = makeCoordinator(
      authService: authService,
      credentialStore: try makeValidatedCredentialStore()
    )

    let firstResult = await coordinator.performBackgroundSync(lease: grantedBackgroundLease())

    XCTAssertFalse(firstResult)
    XCTAssertTrue(authService.requiresSubscriptionAction)
    XCTAssertTrue(authService.isSignedIn)

    let secondResult = await coordinator.performBackgroundSync(lease: grantedBackgroundLease())

    XCTAssertTrue(secondResult)
    XCTAssertFalse(authService.requiresSubscriptionAction)
    XCTAssertEqual(syncRequestCount.value, 2)
    XCTAssertEqual(subscriptionSessionRequestCount.value, 0)
  }

  func testHostedEnrollmentResumesOneFreshDownloadUnderOriginalOwner() async throws {
    try await verifyHostedEnrollmentReplacement(repeatedDenial: false)
  }

  func testRepeatedSubscriptionDenialCannotCreateSecondReplacementAttempt() async throws {
    try await verifyHostedEnrollmentReplacement(repeatedDenial: true)
  }

  private func verifyHostedEnrollmentReplacement(repeatedDenial: Bool) async throws {
    let attempts = LockIsolated(0)
    let subscriptionSessions = LockIsolated(0)
    let responseHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    let subscriptionRequiredHandler = errorResponseHandler(
      statusCode: 401,
      code: "active_subscription_required",
      message: "An active PumpSync subscription is required."
    )
    URLProtocolStub.requestHandler = { request in
      let attempt = attempts.withValue { value in
        value += 1
        return value
      }
      if attempt == 1 || repeatedDenial {
        return try subscriptionRequiredHandler(request)
      }
      return try responseHandler(request)
    }
    let authService = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!),
      sessionStore: nil,
      currentEntitlementJWS: { "active-transaction" },
      createSubscriptionSession: { _ in
        subscriptionSessions.withValue { $0 += 1 }
        return BackendSessionResponse(
          accessToken: "replacement-access-token",
          expiresAt: Date().addingTimeInterval(3_600),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: RecoveringDeviceSessionProofProvider()
    )
    authService.applyScreenshotSession(serviceMode: "hosted")
    let diagnostics = makeDiagnostics()
    let coordinator = makeCoordinator(
      authService: authService,
      credentialStore: try makeValidatedCredentialStore(),
      diagnostics: diagnostics
    )

    let result = await coordinator.run(reason: .background, lease: grantedBackgroundLease())

    XCTAssertEqual(result, repeatedDenial ? .failed : .completed)
    XCTAssertEqual(attempts.value, 2)
    XCTAssertEqual(subscriptionSessions.value, 1)
    XCTAssertEqual(authService.accessToken, "replacement-access-token")
    XCTAssertTrue(diagnostics.entries.filter { $0.title == "Sync started" }.allSatisfy { $0.message == "Reason: background" })
    if repeatedDenial {
      guard case .failed(let failure) = coordinator.operationState else { return XCTFail("Expected a terminal subscription warning") }
      XCTAssertEqual(failure.recovery, .openSubscription)
    } else {
      XCTAssertEqual(coordinator.operationState, .idle)
    }
  }

  func testSubscriptionSessionRecoveryClearsWarningAndStartsOneSync() async throws {
    URLProtocolStub.requestHandler = errorResponseHandler(
      statusCode: 401,
      code: "active_subscription_required",
      message: "An active PumpSync subscription is required."
    )
    let authService = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!),
      sessionStore: nil,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: StubDeviceSessionProofProvider()
    )
    authService.applyScreenshotSession(serviceMode: "hosted")
    let coordinator = makeCoordinator(
      authService: authService,
      credentialStore: try makeValidatedCredentialStore()
    )
    await coordinator.sync(reason: .manual)

    authService.applyScreenshotSession(serviceMode: "hosted")
    URLProtocolStub.requestHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    let foreground = ForegroundRecoveryController(setVisible: { coordinator.setForegroundActive($0) }) {
      _ = await coordinator.refreshIfStale(reason: .appOpen)
    }
    foreground.setScenePhase(.active)

    await waitUntil { coordinator.lastMessage == "No new pump samples were returned." }
    guard case .succeeded = coordinator.operationState else {
      return XCTFail("expected subscription recovery to replace the stale warning with a successful sync")
    }
  }

  func testLateStoreKitRecoveryAfterBootstrapReconcilesOneAppOpenSyncAndFreshness() async throws {
    let restored = BackendSessionResponse(accessToken: "late-storekit", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource")
    let auth = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "LateStoreKit-\(UUID().uuidString)")!),
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in restored }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: RecoveringDeviceSessionProofProvider())
    let count = LockIsolated(0)
    let response = syncResponseHandler(samples: [sample(externalId: "late-storekit")], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in count.withValue { $0 += 1 }; return try response(request) }
    let health = FakeHealthKitService()
    let diagnostics = makeDiagnostics()
    let coordinator = makeCoordinator(authService: auth, credentialStore: try makeValidatedCredentialStore(), healthKitService: health, diagnostics: diagnostics)
    var bootstraps = 0
    let foreground = ForegroundRecoveryController(setVisible: { coordinator.setForegroundActive($0) }) {
      bootstraps += 1
      _ = await coordinator.reconcileForegroundRecovery()
    }
    foreground.observeSessionRecovery(auth, syncCoordinator: coordinator)
    foreground.setScenePhase(.active)
    await waitUntil { bootstraps == 1 && !foreground.isRecovering }
    XCTAssertFalse(coordinator.isSyncing)
    guard case .failed = coordinator.operationState else { return XCTFail("Unavailable bootstrap auth must end its owner") }
    XCTAssertEqual(count.value, 0)
    var finishedTransactions = 0
    await auth.handleActiveSubscriptionTransactionUpdate(signedTransactionInfo: "verified-fixture", diagnosticSummary: "fixture-active") {
      finishedTransactions += 1
    }
    XCTAssertEqual(finishedTransactions, 1)
    await waitUntil { health.savedSamples.count == 1 && !coordinator.isSyncing }
    XCTAssertEqual(count.value, 1)
    XCTAssertEqual(health.savedSamples.map(\.externalId), ["late-storekit"])
    XCTAssertEqual(bootstraps, 2)
    XCTAssertTrue(diagnostics.entries.contains { $0.title == "Sync started" && $0.message == "Reason: appOpen" })
    await waitUntil { !foreground.isRecovering }
    foreground.reconcileRecovery()
    await waitUntil { bootstraps == 3 && !foreground.isRecovering }
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(count.value, 1, "Reconciliation must reevaluate freshness")
  }

  func testBackgroundOnlySurvivorCannotRequestInteractiveSubscriptionRecoveryAfterDownload() async throws {
    try await verifyBackgroundOnlyRecoveryHandoff(revokeDuringEntitlementLookup: false)
  }

  func testForegroundLeaseEndingDuringEntitlementLookupFencesInteractiveFallback() async throws {
    try await verifyBackgroundOnlyRecoveryHandoff(revokeDuringEntitlementLookup: true)
  }

  private func verifyBackgroundOnlyRecoveryHandoff(revokeDuringEntitlementLookup: Bool) async throws {
    let downloadEntered = expectation(description: "foreground download entered")
    let releaseDownload = DispatchSemaphore(value: 0)
    let entitlementEntered = revokeDuringEntitlementLookup ? expectation(description: "entitlement lookup entered") : nil
    let entitlementGate = SyncRecoveryGate()
    let interactiveLookups = LockIsolated(0)
    let enrollments = LockIsolated(0)
    let requests = LockIsolated(0)
    let auth = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "PolicyHandoff-\(UUID().uuidString)")!),
      currentEntitlementJWS: {
        if revokeDuringEntitlementLookup { entitlementEntered?.fulfill(); await entitlementGate.wait() }
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: { interactiveLookups.withValue { $0 += 1 }; return "verified-fixture" },
      createSubscriptionSession: { _ in
        enrollments.withValue { $0 += 1 }
        return BackendSessionResponse(accessToken: "replacement-fixture", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource")
      }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: RecoveringDeviceSessionProofProvider())
    auth.applyScreenshotSession(serviceMode: "hosted")
    let original = auth.session
    let denial = errorResponseHandler(statusCode: 401, code: "active_subscription_required", message: "Subscription required.")
    let response = syncResponseHandler(samples: [], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in
      let number = requests.withValue { $0 += 1; return $0 }
      if number == 1 {
        downloadEntered.fulfill()
        _ = releaseDownload.wait(timeout: .now() + 5)
        return try denial(request)
      }
      return try response(request)
    }
    let health = FakeHealthKitService()
    let metadata = makeSyncMetadataStore()
    let coordinator = makeCoordinator(authService: auth, credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    let foreground = Task { await coordinator.run(reason: .manual) }
    await fulfillment(of: [downloadEntered], timeout: 2)
    let background = Task { await coordinator.run(reason: .background, lease: grantedBackgroundLease()) }
    for _ in 0..<10 { await Task.yield() }
    if !revokeDuringEntitlementLookup { coordinator.setForegroundActive(false) }
    releaseDownload.signal()
    if revokeDuringEntitlementLookup {
      await fulfillment(of: [try XCTUnwrap(entitlementEntered)], timeout: 2)
      coordinator.setForegroundActive(false)
      await entitlementGate.open()
    }
    let foregroundResult = await foreground.value
    let backgroundResult = await background.value
    XCTAssertEqual(foregroundResult, .canceled)
    XCTAssertEqual(backgroundResult, .failed)
    XCTAssertEqual(interactiveLookups.value, 0, "A background grant cannot request StoreKit UI")
    XCTAssertEqual(enrollments.value, 0)
    XCTAssertEqual(requests.value, 1)
    XCTAssertEqual(auth.session, original)
    XCTAssertTrue(health.savedConcentrations.isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
  }

  func testBackgroundSyncRequiresAnExplicitFiniteGrant() async throws {
    URLProtocolStub.requestHandler = { _ in XCTFail("Unowned background work cannot submit"); throw APIClientError.invalidResponse }
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore())
    let unowned = await coordinator.run(reason: .background)
    let unlimited = await coordinator.run(reason: .background, lease: SyncExecutionLease(kind: .background))
    XCTAssertEqual(unowned, .deferred(.executionLeaseExpired))
    XCTAssertEqual(unlimited, .deferred(.executionLeaseExpired))
  }

  func testForegroundBootstrapCapturesCredentialGuardsBeforeRecoveringAuth() async throws {
    let credentials = try makeValidatedCredentialStore()
    let initialRevision = credentials.revision
    let restored = BackendSessionResponse(accessToken: "bootstrap-restored", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource")
    let auth = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "BootstrapGuards-\(UUID().uuidString)")!),
      currentEntitlementJWS: {
        try credentials.saveValidated(.init(username: "replacement-fixture", password: "replacement-fixture", region: "us"))
        return "verified-fixture"
      }, createSubscriptionSession: { _ in restored }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: RecoveringDeviceSessionProofProvider())
    URLProtocolStub.requestHandler = { _ in XCTFail("A replaced pump account cannot inherit bootstrap work"); throw APIClientError.invalidResponse }
    let health = FakeHealthKitService()
    let metadata = makeSyncMetadataStore()
    let coordinator = makeCoordinator(authService: auth, credentialStore: credentials, healthKitService: health, syncMetadataStore: metadata)
    let outcome = await coordinator.reconcileForegroundRecovery()
    XCTAssertEqual(outcome, .contextReplaced)
    XCTAssertTrue(auth.isSignedIn)
    XCTAssertGreaterThan(credentials.revision, initialRevision)
    XCTAssertFalse(coordinator.isSyncing)
    XCTAssertTrue(health.savedSamples.isEmpty)
    XCTAssertNil(metadata.metadata.lastAttemptAt)
  }

  func testFreshForegroundBootstrapStillRenewsAuthBeforeSkippingDownload() async throws {
    try await verifyForegroundBootstrapFreshness(forcedOverlap: false)
  }

  func testManualAndGrantedBackgroundJoiningFreshBootstrapRequestOneDownloadWithAppOpenTrigger() async throws {
    try await verifyForegroundBootstrapFreshness(forcedOverlap: true)
  }

  private func verifyForegroundBootstrapFreshness(forcedOverlap: Bool) async throws {
    let store = makeSessionStore()
    let expired = BackendSessionResponse(accessToken: "expired-bootstrap", expiresAt: .distantPast, serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "bootstrap-family", refreshToken: "refresh-bootstrap", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
    try store.save(expired)
    let restored = BackendSessionResponse(accessToken: "fresh-bootstrap", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "rotated-bootstrap-family", refreshToken: "fresh-refresh-bootstrap", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
    let proof = RecoveringDeviceSessionProofProvider()
    proof.acceptsRefresh = true
    let auth = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "BootstrapFreshness-\(UUID().uuidString)")!), sessionStore: store,
      currentEntitlementJWS: { XCTFail("Ordinary renewal must not enroll"); throw APIClientError.invalidResponse },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: proof)
    let paths = LockIsolated<[String]>([])
    let entered = forcedOverlap ? expectation(description: "refresh entered") : nil
    let gate = DispatchSemaphore(value: 0)
    let syncResponse = syncResponseHandler(samples: [], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    let data = try JSONCodec.encoder.encode(restored)
    URLProtocolStub.requestHandler = { request in
      paths.withValue { $0.append(request.url!.path) }
      if request.url!.path.hasSuffix("/session/refresh") {
        if forcedOverlap { entered?.fulfill(); _ = gate.wait(timeout: .now() + 5) }
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
      }
      return try syncResponse(request)
    }
    let metadata = makeSyncMetadataStore()
    let credentials = try makeValidatedCredentialStore()
    metadata.recordSuccess(sampleCount: 1, importedCount: 1, completedAt: Date(), watermark: Date().addingTimeInterval(-60), owner: try historyOwner(credentials, auth: auth))
    let prior = metadata.metadata
    let health = FakeHealthKitService()
    let diagnostics = makeDiagnostics()
    let coordinator = makeCoordinator(authService: auth, credentialStore: credentials, healthKitService: health, syncMetadataStore: metadata, diagnostics: diagnostics)
    let outcome: SyncRunOutcome
    if forcedOverlap {
      let bootstrap = Task { await coordinator.reconcileForegroundRecovery() }
      await fulfillment(of: [try XCTUnwrap(entered)], timeout: 2)
      let manual = Task { await coordinator.run(reason: .manual) }
      let background = Task { await coordinator.run(reason: .background, lease: grantedBackgroundLease()) }
      for _ in 0..<10 { await Task.yield() }
      gate.signal()
      outcome = await bootstrap.value
      let manualResult = await manual.value
      let backgroundResult = await background.value
      XCTAssertEqual(manualResult, .completed)
      XCTAssertEqual(backgroundResult, .completed)
      XCTAssertEqual(paths.value, ["/api/v1/session/refresh", "/api/v1/sync/tandem"])
      XCTAssertEqual(diagnostics.entries.filter { $0.title == "Sync started" }.map(\.message), ["Reason: appOpen"])
    } else {
      outcome = await coordinator.reconcileForegroundRecovery()
      XCTAssertEqual(paths.value, ["/api/v1/session/refresh"])
      XCTAssertEqual(metadata.metadata, prior)
    }
    XCTAssertEqual(outcome, forcedOverlap ? .completed : .skippedFresh)
    XCTAssertEqual(auth.accessToken, "fresh-bootstrap")
    XCTAssertTrue(health.savedSamples.isEmpty)
    XCTAssertFalse(coordinator.isSyncing)
  }

  func testFreshReconciliationPreservesDismissedCompletionPresentation() async throws {
    URLProtocolStub.requestHandler = { _ in XCTFail("A fresh reconciliation cannot download"); throw APIClientError.invalidResponse }
    let metadata = makeSyncMetadataStore()
    let auth = makeSignedInAuthService()
    let credentials = try makeValidatedCredentialStore()
    metadata.recordSuccess(sampleCount: 1, importedCount: 1, completedAt: Date(), watermark: Date(), owner: try historyOwner(credentials, auth: auth))
    let coordinator = makeCoordinator(authService: auth, credentialStore: credentials, syncMetadataStore: metadata)
    coordinator.applyScreenshotSuccess()
    coordinator.dismissNotification()
    let prior = coordinator.operationState
    let result = await coordinator.reconcileForegroundRecovery()
    XCTAssertEqual(result, .skippedFresh)
    XCTAssertEqual(coordinator.operationState, prior)
    XCTAssertTrue(coordinator.isNotificationDismissed)
    XCTAssertFalse(coordinator.isSyncing)
  }

  func testTypedPrerequisiteBlocksDoNotDownloadOrMutateSuccess() async throws {
    URLProtocolStub.requestHandler = { _ in XCTFail("Blocked prerequisites cannot download"); throw APIClientError.invalidResponse }
    let noCredentials = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: makeCredentialStore())
    let missingCredentials = await noCredentials.run(reason: .manual)
    XCTAssertEqual(missingCredentials, .blocked(.credentials))
    let metadata = makeSyncMetadataStore()
    let noHealth = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore(), healthKitService: FakeHealthKitService(hasAnyWritePermission: false), syncMetadataStore: metadata)
    let missingHealth = await noHealth.run(reason: .appOpen)
    XCTAssertEqual(missingHealth, .blocked(.healthPermission))
    XCTAssertNil(metadata.metadata.lastAttemptAt)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
  }

  func testExpiredExecutionLeaseReturnsExplicitDeferralWithoutRequest() async throws {
    let lease = SyncExecutionLease(kind: .background, deadline: .distantPast)
    URLProtocolStub.requestHandler = { _ in XCTFail("Expired grants cannot submit a request"); throw APIClientError.invalidResponse }
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore())
    let result = await coordinator.run(reason: .background, lease: lease)
    XCTAssertEqual(result, .deferred(.executionLeaseExpired))
    XCTAssertFalse(coordinator.isSyncing)
  }

  func testForegroundCancellationRetainsLateCommittedAuthWithoutResumingIntent() async throws {
    try await verifyRecoveryAfterLeaseEnds(foregroundCancellation: true)
  }

  func testBackgroundExpirationRetainsCommittedAuthWithoutStartingDownload() async throws {
    try await verifyRecoveryAfterLeaseEnds(foregroundCancellation: false)
  }

  func testActualBackgroundDeadlineRetainsLateAuthWithoutStartingUnownedDownload() async throws {
    try await verifyRecoveryAfterLeaseEnds(foregroundCancellation: false, timesOut: true)
  }

  private func verifyRecoveryAfterLeaseEnds(foregroundCancellation: Bool, timesOut: Bool = false) async throws {
    let gate = SyncRecoveryGate()
    let started = expectation(description: "auth submission")
    let store = makeSessionStore()
    if !foregroundCancellation { try store.markHostedReenrollmentPending() }
    let restored = BackendSessionResponse(accessToken: "committed-after-lease", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource")
    let auth = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0),
      configurationStore: BackendConfigurationStore(defaults: UserDefaults(suiteName: "LeaseEnds-\(UUID().uuidString)")!), sessionStore: store,
      currentEntitlementJWS: { "verified-fixture" },
      createSubscriptionSession: { _ in started.fulfill(); await gate.wait(); return restored },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: RecoveringDeviceSessionProofProvider())
    let downloaded = LockIsolated(0)
    let response = syncResponseHandler(samples: [], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in downloaded.withValue { $0 += 1 }; return try response(request) }
    let health = FakeHealthKitService()
    let metadata = makeSyncMetadataStore()
    let coordinator = makeCoordinator(authService: auth, credentialStore: try makeValidatedCredentialStore(), healthKitService: health, syncMetadataStore: metadata)
    var reconciliations = 0
    let foreground = ForegroundRecoveryController(setVisible: { coordinator.setForegroundActive($0) }) {
      reconciliations += 1
      if reconciliations > 1 { _ = await coordinator.reconcileForegroundRecovery() }
    }
    foreground.observeSessionRecovery(auth, syncCoordinator: coordinator)
    foreground.setScenePhase(.active)
    await waitUntil { !foreground.isRecovering }
    let lease = SyncExecutionLease(kind: foregroundCancellation ? .foreground : .background, deadline: Date().addingTimeInterval(30))
    let work = Task {
      if timesOut {
        let outcome = await BackgroundExecutionDeadline.run(timeout: .milliseconds(100), lease: lease) {
          await coordinator.run(reason: .background, lease: lease).succeeded
        }
        XCTAssertEqual(outcome, .timedOut)
        return SyncRunOutcome.deferred(.executionLeaseExpired)
      }
      return await coordinator.run(reason: foregroundCancellation ? .manual : .background, lease: lease)
    }
    await fulfillment(of: [started], timeout: 2)
    if foregroundCancellation { coordinator.setForegroundActive(false) }
    else if !timesOut { lease.revoke() }
    if timesOut || foregroundCancellation {
      _ = await work.value
      await waitUntil { !coordinator.isSyncing }
    }
    await gate.open()
    let result = await work.value
    await waitUntil { auth.accessToken == "committed-after-lease" }
    await waitUntil { !foreground.isRecovering }
    XCTAssertEqual(reconciliations, 1, "Late auth after an ended intent must await a new scene or system owner")
    XCTAssertEqual(result, foregroundCancellation ? .canceled : .deferred(.executionLeaseExpired))
    XCTAssertEqual(store.loadValidSession()?.accessToken, "committed-after-lease", "Auth remains durably repairable after its sync lease ends")
    XCTAssertEqual(downloaded.value, 0)
    XCTAssertTrue(health.savedSamples.isEmpty)
    XCTAssertNil(metadata.metadata.lastSuccessfulSyncAt)
    XCTAssertFalse(coordinator.isSyncing)
    coordinator.setForegroundActive(true)
    let nextOwnerResult = await coordinator.run(reason: .appOpen)
    XCTAssertEqual(nextOwnerResult, .completed)
    XCTAssertEqual(downloaded.value, 1)
  }

  func testManualAppOpenAndBackgroundOverlapShareOneDownloadAndPreserveManualTrigger() async throws {
    let entered = expectation(description: "download entered")
    let gate = DispatchSemaphore(value: 0)
    let count = LockIsolated(0)
    let response = syncResponseHandler(samples: [], effectiveMinDate: Date(timeIntervalSince1970: 1_000_000), effectiveMaxDate: Date())
    URLProtocolStub.requestHandler = { request in
      count.withValue { $0 += 1 }
      entered.fulfill()
      _ = gate.wait(timeout: .now() + 5)
      return try response(request)
    }
    let coordinator = makeCoordinator(authService: makeSignedInAuthService(), credentialStore: try makeValidatedCredentialStore())
    let manual = Task { await coordinator.run(reason: .manual) }
    await fulfillment(of: [entered], timeout: 2)
    let foreground = Task { await coordinator.refreshIfStale(reason: .appOpen) }
    let background = Task { await coordinator.run(reason: .background, lease: grantedBackgroundLease()) }
    for _ in 0..<10 { await Task.yield() }
    guard case .running(let progress) = coordinator.operationState else { gate.signal(); return XCTFail("Expected shared work") }
    XCTAssertEqual(progress.trigger, .manual)
    manual.cancel()
    gate.signal()
    let manualResult = await manual.value
    let foregroundResult = await foreground.value
    let backgroundResult = await background.value
    XCTAssertEqual(manualResult, .canceled)
    XCTAssertEqual(foregroundResult, .completed)
    XCTAssertEqual(backgroundResult, .completed)
    XCTAssertEqual(count.value, 1)
  }

  func testRefreshIfStaleSkipsSyncWhenRecentlySuccessful() async throws {
    let syncMetadataStore = makeSyncMetadataStore()
    let auth = makeSignedInAuthService()
    let credentials = try makeValidatedCredentialStore()
    syncMetadataStore.recordSuccess(sampleCount: 1, importedCount: 1, completedAt: Date(), watermark: Date(), owner: try historyOwner(credentials, auth: auth))
    let diagnostics = makeDiagnostics()
    // No requestHandler installed: if sync() were reached, the client would
    // fail with badServerResponse instead of silently succeeding, so a
    // non-nil lastMessage here would prove the guard didn't hold.
    let coordinator = makeCoordinator(
      authService: auth,
      credentialStore: credentials,
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

  func testBackgroundSyncRunsWhenRecentlySuccessful() async throws {
    let syncMetadataStore = makeSyncMetadataStore()
    let auth = makeSignedInAuthService()
    let credentials = try makeValidatedCredentialStore()
    syncMetadataStore.recordSuccess(sampleCount: 1, importedCount: 1, completedAt: Date(), watermark: Date(), owner: try historyOwner(credentials, auth: auth))
    let diagnostics = makeDiagnostics()
    let requestCount = LockIsolated(0)
    let responseHandler = syncResponseHandler(
      samples: [],
      effectiveMinDate: Date(timeIntervalSince1970: 1_000_000),
      effectiveMaxDate: Date(timeIntervalSince1970: 1_100_000)
    )
    URLProtocolStub.requestHandler = { request in
      requestCount.withValue { $0 += 1 }
      return try responseHandler(request)
    }
    let coordinator = makeCoordinator(
      authService: auth,
      credentialStore: credentials,
      syncMetadataStore: syncMetadataStore,
      diagnostics: diagnostics
    )

    let succeeded = await coordinator.performBackgroundSync(lease: grantedBackgroundLease())

    XCTAssertTrue(succeeded)
    XCTAssertEqual(requestCount.value, 1)
    XCTAssertTrue(diagnostics.entries.contains {
      $0.title == "Background sync policy evaluated"
        && $0.message?.contains("reason=background decision=sync policy=grantedTask") == true
    })
    XCTAssertFalse(diagnostics.entries.contains { $0.title == "Sync skipped" })
  }

  func testBackgroundSyncReportsFailureWhenConnectionRecoveryFails() async throws {
    let coordinator = makeCoordinator(
      authService: makeSignedOutAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      healthKitService: FakeHealthKitService(hasAnyWritePermission: true)
    )

    let succeeded = await coordinator.performBackgroundSync(lease: grantedBackgroundLease())

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
    let background = Task { await coordinator.performBackgroundSync(lease: grantedBackgroundLease()) }
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
        baseURL: AppConstants.defaultAPIBaseURL,
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

  func testTandemSourceFailureExplainsProviderErrorAndPreservesConnection() async throws {
    let authService = makeSignedInAuthService()
    let credentialStore = try makeValidatedCredentialStore()
    let backendMessage = "Tandem Source returned an unexpected response. Try again later."
    URLProtocolStub.requestHandler = errorResponseHandler(statusCode: 502, code: "tandem_source_error", message: backendMessage)

    let coordinator = makeCoordinator(authService: authService, credentialStore: credentialStore)
    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, backendMessage)
    XCTAssertTrue(authService.isSignedIn)
    XCTAssertTrue(credentialStore.hasValidatedCredentials)
    guard case .failed(let failure) = coordinator.operationState else {
      return XCTFail("Expected a visible sync failure")
    }
    XCTAssertEqual(failure.recovery, .waitAndRetry)
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
    importedSampleLedger: (any SyncSampleLedger)? = nil,
    syncMetadataStore: SyncMetadataStore? = nil,
    diagnostics: DiagnosticsLogStore? = nil
  ) -> SyncCoordinator {
    let coordinator = SyncCoordinator(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0),
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
    coordinator.setForegroundActive(true)
    return coordinator
  }

  private func grantedBackgroundLease() -> SyncExecutionLease {
    SyncExecutionLease(kind: .background, deadline: Date().addingTimeInterval(30))
  }

  private func makeSignedInAuthService(configuration: BackendConfigurationStore? = nil) -> AuthService {
    let service = AuthService(
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0),
      configurationStore: configuration ?? BackendConfigurationStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!),
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
      apiClient: PumpSyncAPIClient(baseURL: AppConstants.defaultAPIBaseURL, urlSession: .shared, maxRetryCount: 0),
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

  private func makeSessionStore() -> BackendSessionStore {
    BackendSessionStore(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)")
    )
  }

  private func renewableHostedSession() -> BackendSessionResponse {
    BackendSessionResponse(
      accessToken: "hosted-access-token",
      expiresAt: .distantFuture,
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "session-family",
      refreshToken: "refresh-token",
      refreshTokenExpiresAt: .distantFuture,
      refreshTokenAbsoluteExpiresAt: .distantFuture
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

  private func historyOwner(_ credentials: TandemCredentialStore, auth: AuthService) throws -> TandemSyncOwner {
    TandemSyncOwner(accountId: try XCTUnwrap(credentials.accountId), backendIdentity: try XCTUnwrap(auth.importConfigurationSnapshot.backendIdentity))
  }

  private func makeSyncMetadataStore() -> SyncMetadataStore {
    SyncMetadataStore(defaults: UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)")!)
  }

  private final class StubDeviceSessionProofProvider: DeviceSessionProofProviding {
  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition { .ready }
  func invalidateHostedProofOperation() {}
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

    func hostedProofKeyID(requestId: String) throws -> String { "app-attest-key" }

    func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool { keyId == "app-attest-key" }

    func refreshRequest(
      session: BackendSessionResponse,
      installationId: String,
      mode: BackendAccessMode
    ) async throws -> SessionRefreshRequest {
      throw APIClientError.invalidResponse
    }
  }

  private final class RecoveringDeviceSessionProofProvider: DeviceSessionProofProviding {
  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition { .ready }
  func invalidateHostedProofOperation() {}
    var acceptsRefresh = false
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

    func hostedProofKeyID(requestId: String) throws -> String { "app-attest-key" }

    func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool { keyId == "app-attest-key" }

    func refreshRequest(
      session: BackendSessionResponse,
      installationId: String,
      mode: BackendAccessMode
    ) async throws -> SessionRefreshRequest {
      guard acceptsRefresh else { throw APIClientError.invalidResponse }
      return SessionRefreshRequest(installationId: installationId, refreshToken: session.refreshToken, requestId: UUID().uuidString, issuedAt: Date(), proof: "test-proof")
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

private actor SyncRecoveryGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false
  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }
}
