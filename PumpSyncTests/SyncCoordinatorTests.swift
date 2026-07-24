import XCTest
@testable import PumpSync

@MainActor
private final class FakeHealthKitService: SyncHealthWriting {
  var hasAnyWritePermission: Bool
  var saveResult: Result<Int, Error> = .success(0)
  private(set) var refreshAuthorizationStatusCallCount = 0
  private(set) var savedSamples: [SampleDTO] = []

  init(hasAnyWritePermission: Bool = true) {
    self.hasAnyWritePermission = hasAnyWritePermission
  }

  func refreshAuthorizationStatus() {
    refreshAuthorizationStatusCallCount += 1
  }

  func save(samples: [SampleDTO]) async throws -> Int {
    savedSamples = samples
    return try saveResult.get()
  }
}

private struct StubTandemSyncResponse: Encodable {
  let cursor: String?
  let samples: [SampleDTO]
  let effectiveMinDate: Date
  let effectiveMaxDate: Date
}

@MainActor
final class SyncCoordinatorTests: XCTestCase {
  override func tearDown() {
    URLProtocolStub.requestHandler = nil
    super.tearDown()
  }

  func testSyncBlockedWhenNotAuthenticated() async throws {
    let diagnostics = makeDiagnostics()
    let coordinator = makeCoordinator(
      authService: makeSignedOutAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      diagnostics: diagnostics
    )

    await coordinator.sync(reason: .manual)

    XCTAssertEqual(coordinator.lastMessage, "Connect PumpSync before syncing.")
    XCTAssertFalse(coordinator.isSyncing)
    XCTAssertEqual(diagnostics.entries.first?.title, "Sync blocked")
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
    fakeHealthKit.saveResult = .success(2)
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
    // The watermark must come from the server's reported effective window,
    // minus the overlap, not a client-side Date() — this is the I4 fix.
    XCTAssertEqual(syncMetadataStore.metadata.lastSuccessfulSyncAt, effectiveMaxDate.addingTimeInterval(-24 * 60 * 60))
    XCTAssertEqual(diagnostics.entries.first?.title, "Sync completed")
  }

  func testSyncDeduplicatesAlreadyImportedSamplesBeforeSavingToHealthKit() async throws {
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    fakeHealthKit.saveResult = .success(1)
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
    XCTAssertNotNil(syncMetadataStore.metadata.lastErrorMessage)
  }

  func testRefreshIfStaleSkipsSyncWhenRecentlySuccessful() async throws {
    let syncMetadataStore = makeSyncMetadataStore()
    syncMetadataStore.recordSuccess(sampleCount: 1, importedCount: 1, watermark: Date())
    // No requestHandler installed: if sync() were reached, the client would
    // fail with badServerResponse instead of silently succeeding, so a
    // non-nil lastMessage here would prove the guard didn't hold.
    let coordinator = makeCoordinator(
      authService: makeSignedInAuthService(),
      credentialStore: try makeValidatedCredentialStore(),
      syncMetadataStore: syncMetadataStore
    )

    await coordinator.refreshIfStale(reason: .appOpen)

    XCTAssertNil(coordinator.lastMessage)
  }

  func testRefreshIfStaleSyncsWhenNoPriorSuccessfulSync() async throws {
    let fakeHealthKit = FakeHealthKitService(hasAnyWritePermission: true)
    fakeHealthKit.saveResult = .success(0)
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

  // MARK: - Fixtures

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
      }
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
      }
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
    effectiveMaxDate: Date,
    cursor: String? = nil
  ) -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
    { request in
      let body = StubTandemSyncResponse(cursor: cursor, samples: samples, effectiveMinDate: effectiveMinDate, effectiveMaxDate: effectiveMaxDate)
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
