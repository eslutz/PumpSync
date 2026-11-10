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
    // A rapid return to the screen cannot overlap the canceled owner's
    // deferred cleanup while its request is still unwinding.
    await controller.connect()
    XCTAssertEqual(requests, 1)
    continuation?.resume()
    await task.value
    XCTAssertTrue(controller.canConnect)
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

  func testURLValidationAcceptsRootAndCustomHTTPSBasePathsWithoutAddingAPI() {
    for value in ["https://example.com", "https://example.com/api", "https://example.com/pumpsync/custom", "https://example.com:8443/custom", "https://[::1]:8443/custom", "https://[2001:db8::1]:8443/custom"] {
      XCTAssertEqual(BackendConfigurationStore.validatedSelfHostedURL(from: value)?.absoluteString, value)
    }
    XCTAssertEqual(BackendConfigurationStore.validatedSelfHostedURL(from: " https://example.com/custom/// ")?.absoluteString, "https://example.com/custom")
    XCTAssertEqual(BackendConfigurationStore.validatedSelfHostedURL(from: "https://example.com/")?.absoluteString, "https://example.com")
  }

  func testURLValidationRejectsHTTPAndNonEndpointComponents() {
    for value in ["https://user:password@example.com/api", "https://example.com/api?token=secret", "https://example.com/api#fragment", "example.com/api", "http://remote.example/api", "http://localhost:8080/api", "http://127.0.0.1:8080/api", "http://[::1]:8080/api", "ftp://example.com/api", "https:///api"] {
      XCTAssertNil(BackendConfigurationStore.validatedSelfHostedURL(from: value))
    }
  }

  func testSubscriptionControllerStartsFromCommittedSettingsAndOwnsItsRequest() throws {
    let services = AppServices.screenshotFixture()
    let configuration = services.backendConfigurationStore
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://active.example/custom"
    let storage = ConnectionActivationStorage(root: Persistence())
    let settings = ConnectionSettingsController(configuration: configuration, auth: services.authService,
      api: services.apiClient, sync: services.syncCoordinator, storage: storage, diagnostics: services.diagnosticsLogStore) { api, candidate, persistence, _ in
        AuthService(apiClient: api, configurationStore: candidate, sessionStore: BackendSessionStore(keychain: persistence),
          currentEntitlementJWS: { "fixture" }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
          createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: ConnectionProof())
      }
    settings.mode = .hosted
    settings.serverURL = "https://unsaved.example/ignored"
    let subscription = settings.independentController()
    XCTAssertEqual(subscription.mode, .selfHosted)
    XCTAssertEqual(subscription.serverURL, "https://active.example/custom")
    XCTAssertEqual(subscription.committedMode, .selfHosted, "Restore must use the committed service, not the Settings picker draft")
    subscription.mode = .hosted
    let request = try XCTUnwrap(subscription.prepareSubscription())
    settings.cancel() // A delayed outgoing-screen callback cannot cancel the destination.
    XCTAssertTrue(subscription.isCurrentSubscriptionRequest(request))
    XCTAssertTrue(subscription.candidateAuth === request.auth)
    XCTAssertTrue(services.authService.isReplacingConnection)
    subscription.cancel()
    XCTAssertFalse(subscription.isCurrentSubscriptionRequest(request))
    subscription.finishSubscription(request, verified: true)
    XCTAssertEqual(configuration.mode, .selfHosted)
    XCTAssertEqual(subscription.mode, .selfHosted)
    XCTAssertEqual(subscription.serverURL, "https://active.example/custom")
    XCTAssertFalse(services.authService.isReplacingConnection)
  }

  func testDismissingSameHostedPurchaseInvalidatesItsLateCallbacks() throws {
    let services = AppServices.screenshotFixture()
    let controller = ConnectionSettingsController(configuration: services.backendConfigurationStore,
      auth: services.authService, api: services.apiClient, sync: services.syncCoordinator,
      storage: ConnectionActivationStorage(root: Persistence()), diagnostics: services.diagnosticsLogStore)
    let old = try XCTUnwrap(controller.prepareSubscription())
    controller.finishSubscription(old, verified: false)
    XCTAssertFalse(controller.isCurrentSubscriptionRequest(old))
    let newer = try XCTUnwrap(controller.prepareSubscription())
    controller.finishSubscription(old, verified: true)
    XCTAssertTrue(controller.isCurrentSubscriptionRequest(newer))
    XCTAssertTrue(controller.candidateAuth === newer.auth)
    controller.cancel()
  }

  func testRecognizedSubscriptionConnectsWithoutRestoreAndActivatesAtomically() async throws {
    let services = AppServices.screenshotFixture()
    let root = Persistence()
    let storage = ConnectionActivationStorage(root: root)
    let configuration = services.backendConfigurationStore
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://existing.example/api"
    let store = BackendSessionStore(keychain: storage)
    let live = AuthService(apiClient: services.apiClient, configurationStore: configuration, sessionStore: store,
      currentEntitlementJWS: { throw APIClientError.invalidResponse },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: ConnectionProof())
    live.applyScreenshotSession(serviceMode: "selfHosted")
    let original = try XCTUnwrap(live.authenticatedConnection)
    try store.save(original)
    var reads = 0
    var posts = 0
    let controller = ConnectionSettingsController(configuration: configuration, auth: live, api: services.apiClient,
      sync: services.syncCoordinator, storage: storage, diagnostics: services.diagnosticsLogStore) { api, candidate, persistence, _ in
        let proof = ConnectionProof()
        proof.allowsHostedEnrollment = true
        return AuthService(apiClient: api, configurationStore: candidate, sessionStore: BackendSessionStore(keychain: persistence),
          currentEntitlementJWS: { reads += 1; return "recognized-subscription" },
          syncedCurrentEntitlementJWS: { XCTFail("Connect with recognized access must not restore purchases"); return "unexpected" },
          createSubscriptionSession: { _ in
            posts += 1
            XCTAssertEqual(configuration.mode, .selfHosted, "Draft must stay inactive until its response commits")
            XCTAssertEqual(live.authenticatedConnection, original)
            return BackendSessionResponse(accessToken: "hosted-replacement", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource")
          }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: proof)
      }
    controller.mode = .hosted
    await controller.connect(restorePurchases: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(posts, 1)
    XCTAssertEqual(configuration.mode, .hosted)
    XCTAssertEqual(live.accessToken, "hosted-replacement")
    XCTAssertFalse(live.isReplacingConnection)
    XCTAssertEqual(try store.loadConnection(binding: XCTUnwrap(live.connectionBinding))?.session.accessToken, "hosted-replacement")
  }

  func testControllerCancellationStopsHostedRestoreAndConnectBeforeSubmission() async throws {
    for restorePurchases in [false, true] {
      let services = AppServices.screenshotFixture()
      let storage = ConnectionActivationStorage(root: Persistence())
      let configuration = services.backendConfigurationStore
      let store = BackendSessionStore(keychain: storage)
      let proof = ConnectionProof()
      proof.allowsHostedEnrollment = true
      let proofStarted = expectation(description: "proof started")
      let proofCancelled = expectation(description: "controller cancellation reached proof")
      var releaseProof: CheckedContinuation<Void, Never>?
      proof.beforeHostedEnrollment = {
        await withTaskCancellationHandler {
          await withCheckedContinuation { continuation in
            releaseProof = continuation
            proofStarted.fulfill()
          }
        } onCancel: { proofCancelled.fulfill() }
      }
      var posts = 0
      let live = AuthService(apiClient: services.apiClient, configurationStore: configuration, sessionStore: store,
        currentEntitlementJWS: { "recognized-subscription" },
        createSubscriptionSession: { _ in posts += 1; throw APIClientError.invalidResponse },
        createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: proof)
      let controller = ConnectionSettingsController(configuration: configuration, auth: live, api: services.apiClient,
        sync: services.syncCoordinator, storage: storage, diagnostics: services.diagnosticsLogStore)
      let caller = Task { await controller.connect(restorePurchases: restorePurchases) }
      await fulfillment(of: [proofStarted], timeout: 2)

      // A different screen invokes this, without owning or canceling caller.
      controller.cancel()
      await fulfillment(of: [proofCancelled], timeout: 2)
      releaseProof?.resume()
      await caller.value

      XCTAssertEqual(posts, 0)
      XCTAssertFalse(live.isSignedIn)
      XCTAssertNil(try store.loadAuthJournal())
      XCTAssertFalse(controller.isConnecting)
      XCTAssertTrue(controller.canConnect)
    }
  }

  func testControllerCancellationPreservesAlreadySubmittedHostedResponseCommit() async throws {
    let services = AppServices.screenshotFixture()
    let storage = ConnectionActivationStorage(root: Persistence())
    let configuration = services.backendConfigurationStore
    let store = BackendSessionStore(keychain: storage)
    let proof = ConnectionProof()
    proof.allowsHostedEnrollment = true
    let submitted = expectation(description: "request submitted")
    let committed = expectation(description: "confirmed late response committed")
    var responseContinuation: CheckedContinuation<BackendSessionResponse, Never>?
    let live = AuthService(apiClient: services.apiClient, configurationStore: configuration, sessionStore: store,
      currentEntitlementJWS: { "recognized-subscription" },
      createSubscriptionSession: { _ in
        await withCheckedContinuation { continuation in
          responseContinuation = continuation
          submitted.fulfill()
        }
      }, createSelfHostedSession: { _ in throw APIClientError.invalidResponse }, proofProvider: proof)
    live.configurationDidCommit = { committed.fulfill() }
    var newSyncSignals = 0
    live.setSessionEstablishedHandler { newSyncSignals += 1 }
    let controller = ConnectionSettingsController(configuration: configuration, auth: live, api: services.apiClient,
      sync: services.syncCoordinator, storage: storage, diagnostics: services.diagnosticsLogStore)
    let caller = Task { await controller.connect(restorePurchases: false) }
    await fulfillment(of: [submitted], timeout: 2)
    controller.cancel()
    await caller.value
    responseContinuation?.resume(returning: BackendSessionResponse(
      accessToken: "confirmed-late-response", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource"
    ))
    await fulfillment(of: [committed], timeout: 2)

    XCTAssertEqual(try store.loadConnection(binding: XCTUnwrap(live.connectionBinding))?.session.accessToken, "confirmed-late-response")
    XCTAssertEqual(newSyncSignals, 0, "A canceled owner may retain a confirmed credential but cannot trigger new sync work")
    XCTAssertFalse(controller.isConnecting)
  }
}

@MainActor
private final class ConnectionProof: DeviceSessionProofProviding {
  var allowsHostedEnrollment = false
  var beforeHostedEnrollment: (@MainActor () async -> Void)?
  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition { .ready }
  func invalidateHostedProofOperation() {}
  func hostedEnrollment(challenge: SessionChallengeResponse, installationId: String, signedTransactionInfo: String) async throws -> HostedDeviceEnrollment {
    guard allowsHostedEnrollment else { throw APIClientError.invalidResponse }
    await beforeHostedEnrollment?()
    return HostedDeviceEnrollment(requestId: UUID().uuidString, issuedAt: Date(), challengeToken: challenge.challengeToken, keyId: "fixture", proofKind: "attestation", proof: "fixture")
  }
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
