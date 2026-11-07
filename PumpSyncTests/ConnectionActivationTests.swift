import XCTest
@testable import PumpSync

@MainActor
final class ConnectionActivationTests: XCTestCase {
  private final class Persistence: BackendSessionPersistence {
    var values: [String: Data] = [:]
    var failsWrites = false
    func readData(account: String) throws -> Data? { values[account] }
    func writeData(_ data: Data, account: String) throws {
      if failsWrites { throw KeychainStoreError.invalidData }
      values[account] = data
    }
    func delete(account: String) throws { values[account] = nil }
  }

  func testStagingAndFailedActivationPreserveActiveStorageAndConfiguration() throws {
    let root = Persistence()
    let suite = "Activation.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let configuration = BackendConfigurationStore(defaults: defaults)
    let storage = ConnectionActivationStorage(root: root)
    try storage.writeData(Data("working".utf8), account: "session")
    let original = BackendConnectionDraft(configuration: configuration)
    let draft = BackendConnectionDraft(mode: .selfHosted, serverURL: "https://replacement.example/api", hostedEnvironment: original.hostedEnvironment)
    let pending = try storage.prepare(draft)
    try pending.persistence.writeData(Data("candidate".utf8), account: "session")
    XCTAssertEqual(try storage.readData(account: "session"), Data("working".utf8))
    XCTAssertEqual(BackendConnectionDraft(configuration: configuration), original)
    root.failsWrites = true
    XCTAssertThrowsError(try storage.activate(pending, configuration: configuration))
    XCTAssertEqual(BackendConnectionDraft(configuration: configuration), original)
    XCTAssertEqual(try storage.readData(account: "session"), Data("working".utf8))
  }

  func testCommittedPointerRestoresMatchingConfigurationAndNamespaceAfterRestart() throws {
    let root = Persistence()
    let suite = "ActivationRestart.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let configuration = BackendConfigurationStore(defaults: defaults)
    let storage = ConnectionActivationStorage(root: root)
    let draft = BackendConnectionDraft(mode: .selfHosted, serverURL: "https://new.example/api", hostedEnvironment: configuration.hostedEnvironment)
    let pending = try storage.prepare(draft)
    try pending.persistence.writeData(Data("new-session".utf8), account: "session")
    try storage.activate(pending, configuration: configuration)
    configuration.mode = .hosted // Simulate a stale preferences write after the durable commit.
    let restarted = ConnectionActivationStorage(root: root)
    try restarted.restoreConfiguration(configuration)
    XCTAssertEqual(BackendConnectionDraft(configuration: configuration), draft)
    XCTAssertEqual(try restarted.readData(account: "session"), Data("new-session".utf8))
  }

  func testRecoveryUsesSubmittedHostedJournalRouteForActiveAndPendingNamespaces() throws {
    for activate in [false, true] {
      let root = Persistence()
      let storage = ConnectionActivationStorage(root: root)
      let suite = "JournalRoute.\(UUID())"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let configuration = BackendConfigurationStore(defaults: defaults)
      let draft = BackendConnectionDraft(mode: .hosted, serverURL: "", hostedEnvironment: .sandbox)
      let pending = try storage.prepare(draft)
      if activate { try storage.activate(pending, configuration: configuration) }
      let store = BackendSessionStore(keychain: pending.persistence)
      let committer = AuthSessionCommitter(store: store)
      let binding = AuthConnectionBinding(backendIdentity: ImportSessionSnapshot.canonicalBackendIdentity(AppConstants.hostedAPIBaseURL(for: .production)), mode: .hosted, installationId: configuration.installationId, purpose: .liveImport)
      let operation = try committer.begin(kind: .enrollment, binding: binding, source: nil, proofRequestID: UUID().uuidString, proofKeyID: "fixture")
      try committer.submitted(operation, binding: binding, source: nil)
      if activate {
        try storage.restoreConfiguration(configuration)
        XCTAssertEqual(configuration.hostedEnvironment, .production)
      } else {
        let restored = try storage.prepare(draft)
        XCTAssertEqual(restored.namespace, pending.namespace)
        XCTAssertEqual(restored.draft.hostedEnvironment, .production)
        let retried = try storage.prepare(draft)
        XCTAssertEqual(retried.namespace, pending.namespace)
        XCTAssertEqual(retried.draft.hostedEnvironment, .production)
      }
      XCTAssertEqual(try store.loadAuthJournal()?.operationID, operation)
    }
  }

  func testRecoveryAppliesMatchingAPIURLAlongsideConfiguration() throws {
    let root = Persistence()
    let storage = ConnectionActivationStorage(root: root)
    let suite = "RouteRecovery.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let configuration = BackendConfigurationStore(defaults: defaults)
    let draft = BackendConnectionDraft(mode: .selfHosted, serverURL: "https://restored.example/api", hostedEnvironment: .sandbox)
    try storage.activate(storage.prepare(draft), configuration: configuration)
    let api = PumpSyncAPIClient(baseURL: URL(string: "https://stale.example/api")!, urlSession: .shared)
    try storage.restoreConfiguration(configuration, apiClient: api)
    XCTAssertEqual(api.baseURL.absoluteString, draft.serverURL)
  }

  func testCanceledCandidateCannotActivateLateResponseAndRetryCommitsTheNewConnection() async throws {
    let services = AppServices.screenshotFixture()
    let root = Persistence()
    let storage = ConnectionActivationStorage(root: root)
    let configuration = services.backendConfigurationStore
    let store = BackendSessionStore(keychain: storage)
    let live = AuthService(apiClient: services.apiClient, configurationStore: configuration, sessionStore: store,
      currentEntitlementJWS: { "fixture" }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: ConnectionProof())
    live.applyScreenshotSession(serviceMode: "hosted")
    let original = try XCTUnwrap(live.authenticatedConnection)
    try store.save(original)
    var pause = true
    var continuation: CheckedContinuation<Void, Never>?
    var requests = 0
    let controller = ConnectionSettingsController(configuration: configuration, auth: live, api: services.apiClient,
      sync: services.syncCoordinator, storage: storage, diagnostics: services.diagnosticsLogStore) { api, candidate, persistence, _ in
        AuthService(apiClient: api, configurationStore: candidate, sessionStore: BackendSessionStore(keychain: persistence),
          currentEntitlementJWS: { "fixture" }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
          createSelfHostedSession: { _ in
            requests += 1
            if pause { await withCheckedContinuation { continuation = $0 } }
            return BackendSessionResponse(accessToken: "candidate", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "candidate-family", refreshToken: "candidate-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
          }, proofProvider: ConnectionProof())
      }
    controller.mode = .selfHosted
    controller.serverURL = "https://candidate.example/api"
    let task = Task { await controller.connect() }
    for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
    XCTAssertNotNil(continuation)
    XCTAssertEqual(configuration.mode, .hosted)
    XCTAssertEqual(live.authenticatedConnection, original)
    await controller.connect()
    XCTAssertEqual(requests, 1)
    controller.cancel()
    XCTAssertFalse(live.isReplacingConnection)
    continuation?.resume()
    await task.value
    XCTAssertEqual(configuration.mode, .hosted)
    XCTAssertEqual(live.authenticatedConnection, original)
    pause = false
    controller.mode = .selfHosted
    controller.serverURL = "https://candidate.example/api"
    await controller.connect()
    XCTAssertEqual(configuration.mode, .selfHosted)
    XCTAssertEqual(live.accessToken, "candidate")
    XCTAssertFalse(live.isReplacingConnection)
    XCTAssertEqual(try store.loadConnection(binding: XCTUnwrap(live.connectionBinding))?.session.accessToken, "candidate")
  }

  func testCanceledSubscriptionCallbackPreservesNewRequestAndCleansLateFailedStorage() throws {
    let services = AppServices.screenshotFixture()
    let configuration = services.backendConfigurationStore
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://active.example/api"
    let root = Persistence()
    let storage = ConnectionActivationStorage(root: root)
    let controller = ConnectionSettingsController(configuration: configuration, auth: services.authService, api: services.apiClient,
      sync: services.syncCoordinator, storage: storage, diagnostics: services.diagnosticsLogStore) { api, candidate, persistence, _ in
        AuthService(apiClient: api, configurationStore: candidate, sessionStore: BackendSessionStore(keychain: persistence),
          currentEntitlementJWS: { "fixture" }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
          createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: ConnectionProof())
      }
    controller.mode = .hosted
    let old = try XCTUnwrap(controller.prepareSubscription())
    controller.finishSubscription(old, verified: false)
    controller.mode = .hosted
    let newer = try XCTUnwrap(controller.prepareSubscription())
    XCTAssertNotEqual(old.namespace, newer.namespace)
    controller.finishSubscription(old, verified: true)
    XCTAssertTrue(controller.candidateAuth === newer.auth)
    XCTAssertTrue(services.authService.isReplacingConnection)
    XCTAssertEqual(configuration.mode, .selfHosted)
    let lateAccount = "connection.\(try XCTUnwrap(old.namespace).uuidString).backend.auth.operation-journal.v1"
    root.values[lateAccount] = Data("late failed attempt".utf8)
    controller.subscriptionAttemptFinished(old)
    XCTAssertNil(root.values[lateAccount])
    XCTAssertTrue(controller.candidateAuth === newer.auth)
    controller.finishSubscription(newer, verified: false)
  }

  func testSuccessfulReplacementClearsOnlyPreviousCommitterFailureFence() async throws {
    let services = AppServices.screenshotFixture()
    let root = Persistence()
    let storage = ConnectionActivationStorage(root: root)
    let configuration = services.backendConfigurationStore
    let store = BackendSessionStore(keychain: storage)
    let live = AuthService(apiClient: services.apiClient, configurationStore: configuration, sessionStore: store,
      currentEntitlementJWS: { "fixture" }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: ConnectionProof())
    live.applyScreenshotSession(serviceMode: "hosted")
    try store.save(XCTUnwrap(live.authenticatedConnection))
    root.failsWrites = true
    live.clearSessionForConnectionChange()
    XCTAssertFalse(live.isSignedIn)
    root.failsWrites = false
    let controller = ConnectionSettingsController(configuration: configuration, auth: live, api: services.apiClient,
      sync: services.syncCoordinator, storage: storage, diagnostics: services.diagnosticsLogStore) { api, candidate, persistence, _ in
        AuthService(apiClient: api, configurationStore: candidate, sessionStore: BackendSessionStore(keychain: persistence),
          currentEntitlementJWS: { "fixture" }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
          createSelfHostedSession: { _ in BackendSessionResponse(accessToken: "replacement", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "new", refreshToken: "refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture) }, proofProvider: ConnectionProof())
      }
    controller.mode = .selfHosted
    controller.serverURL = "https://replacement.example/api"
    await controller.connect()
    XCTAssertTrue(live.isSignedIn)
    XCTAssertEqual(live.accessToken, "replacement")
  }

  func testURLValidationRejectsCredentialsQueriesAndMissingAPIPath() {
    for value in ["https://user:password@example.com/api", "https://example.com/api?token=secret", "https://example.com", "http://remote.example/api"] {
      XCTAssertNil(BackendConfigurationStore.validatedSelfHostedURL(from: value))
    }
    XCTAssertEqual(BackendConfigurationStore.validatedSelfHostedURL(from: " https://example.com/api/ ")?.path, "/api")
    XCTAssertNotNil(BackendConfigurationStore.validatedSelfHostedURL(from: "http://localhost:8080/api"))
  }
}

@MainActor
private final class ConnectionProof: DeviceSessionProofProviding {
  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition { .ready }
  func invalidateHostedProofOperation() {}
  func hostedEnrollment(challenge: SessionChallengeResponse, installationId: String, signedTransactionInfo: String) async throws -> HostedDeviceEnrollment { throw APIClientError.invalidResponse }
  func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool { true }
  func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool { true }
  func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
  func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
  func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
  func discardRegisteredHostedKey() throws -> Bool { false }
  func releaseHostedProofOperation(requestId: String) -> Bool { false }
  func selfHostedEnrollment(challenge: SessionChallengeResponse, installationId: String) throws -> SelfHostedDeviceEnrollment {
    SelfHostedDeviceEnrollment(requestId: UUID().uuidString, issuedAt: Date(), challengeToken: challenge.challengeToken, publicKey: "fixture-key", signature: "fixture-signature")
  }
  func hostedProofKeyID(requestId: String) throws -> String { "fixture" }
  func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool { true }
  func refreshRequest(session: BackendSessionResponse, installationId: String, mode: BackendAccessMode) async throws -> SessionRefreshRequest { throw APIClientError.invalidResponse }
}
