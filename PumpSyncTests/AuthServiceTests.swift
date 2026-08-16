import XCTest
@testable import PumpSync

@MainActor
final class AuthServiceTests: XCTestCase {
  func testLoadsValidCachedSessionWithoutCallingStoreKitOrBackend() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let cachedSession = BackendSessionResponse(
      accessToken: "cached-token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(cachedSession)

    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("StoreKit should not be called when a cached session is valid")
        return "unexpected"
      },
      createSubscriptionSession: { _ in
        XCTFail("Backend should not be called when a cached session is valid")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        XCTFail("Backend should not be called when a cached session is valid")
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(service.accessToken, "cached-token")
    XCTAssertTrue(service.isSignedIn)
  }

  func testConcurrentSubscriptionRecoveryCoalescesStoreKitAndBackendWork() async {
    var entitlementCalls = 0
    var backendCalls = 0
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        entitlementCalls += 1
        try await Task.sleep(for: .milliseconds(20))
        return "signed-transaction"
      },
      createSubscriptionSession: { _ in
        backendCalls += 1
        try await Task.sleep(for: .milliseconds(20))
        return BackendSessionResponse(
          accessToken: "token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "hosted",
          dataSourceMode: "tandemSource"
        )
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    async let first: Void = service.recoverSessionIfNeeded()
    async let second: Void = service.recoverSessionIfNeeded()
    _ = await (first, second)

    XCTAssertEqual(entitlementCalls, 1)
    XCTAssertEqual(backendCalls, 1)
    XCTAssertTrue(service.isSignedIn)
  }

  func testUncachedSubscriptionSessionTimesOutWithoutDiscardingEntitlementState() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in
        try await Task.sleep(for: .seconds(1))
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      diagnostics: diagnostics,
      subscriptionSessionTimeout: 0.01,
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertFalse(service.isConnecting)
    XCTAssertFalse(service.isSignedIn)
    XCTAssertTrue(diagnostics.entries.contains { $0.message?.contains("timedOut=true") == true })
  }

  func testSubscriptionSessionTimeoutCancelsTheInFlightBackendOperation() async throws {
    var backendOperationWasCancelled = false
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: { "signed-transaction" },
      createSubscriptionSession: { _ in
        do {
          try await Task.sleep(for: .seconds(1))
          throw APIClientError.invalidResponse
        } catch is CancellationError {
          backendOperationWasCancelled = true
          throw CancellationError()
        }
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      subscriptionSessionTimeout: 0.01,
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()
    try await Task.sleep(for: .milliseconds(20))

    XCTAssertTrue(backendOperationWasCancelled)
  }

  func testSubscriptionRestoreCreatesBackendSession() async {
    let diagnostics = makeDiagnostics()
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("Silent entitlement reads should not be used for explicit restore")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { request in
        XCTAssertEqual(request.signedTransactionInfo, "signed-transaction")
        XCTAssertEqual(request.installationId, configuration.installationId)
        return session
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.connectUsingCurrentSubscription()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "PumpSync subscription active")
    XCTAssertEqual(sessionStore.loadValidSession(), session)
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("Subscription session timing"))
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("PumpSync subscription restored"))
  }

  func testSubscriptionPurchaseCompletionCreatesBackendSession() async {
    let diagnostics = makeDiagnostics()
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Purchase completion should use the signed transaction returned by StoreKit")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { request in
        XCTAssertEqual(request.signedTransactionInfo, "signed-purchase-transaction")
        XCTAssertEqual(request.installationId, configuration.installationId)
        return session
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.activateSubscription(signedTransactionInfo: "signed-purchase-transaction")

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "PumpSync subscription active")
    XCTAssertEqual(sessionStore.loadValidSession(), session)
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("Subscription session timing"))
    XCTAssertTrue(diagnostics.entries.map(\.title).contains("PumpSync subscription purchased"))
  }

  func testSubscriptionRestorePublishesUserSafeErrorAndDiagnostics() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { _ in
        throw APIClientError.httpStatus(401, code: "invalid_token", message: "Subscription validation failed for user@example.com.")
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.connectUsingCurrentSubscription()

    let expectedMessage = "PumpSync could not verify your App Store subscription. Check your Apple Account subscription, then try Restore Subscription again."
    XCTAssertFalse(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertEqual(service.statusMessage, expectedMessage)
    XCTAssertEqual(service.errorMessage, expectedMessage)
    XCTAssertEqual(service.connectionRequiredMessage, expectedMessage)
    let failure = diagnostics.entries.first { $0.title == "Subscription session failed" }
    XCTAssertEqual(failure?.message, "Subscription validation failed for [redacted email].")
  }

  func testSubscriptionRestoreFailurePreservesExistingSession() async throws {
    let diagnostics = makeDiagnostics()
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let existingSession = BackendSessionResponse(
      accessToken: "existing-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(existingSession)
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { _ in
        throw APIClientError.httpStatus(401, code: "invalid_token", message: "Signed App Store payload validation failed.")
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    XCTAssertEqual(service.accessToken, "existing-token")

    await service.connectUsingCurrentSubscription()

    let expectedMessage = "PumpSync could not verify your App Store subscription. Check your Apple Account subscription, then try Restore Subscription again."
    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isConnecting)
    XCTAssertEqual(service.accessToken, "existing-token")
    XCTAssertEqual(service.statusMessage, expectedMessage)
    XCTAssertEqual(service.errorMessage, expectedMessage)
    XCTAssertEqual(sessionStore.loadValidSession(), existingSession)
    XCTAssertNotNil(diagnostics.entries.first { $0.title == "Subscription session failed" })
  }

  func testCancelledPurchasePreservesExistingSession() throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let existingSession = BackendSessionResponse(
      accessToken: "existing-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(existingSession)
    let service = makeSubscriptionService(sessionStore: sessionStore)

    service.recordSubscriptionPurchaseCancelled()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertEqual(service.accessToken, "existing-token")
    XCTAssertEqual(sessionStore.loadValidSession(), existingSession)
  }

  func testPendingPurchasePreservesExistingSession() throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let existingSession = BackendSessionResponse(
      accessToken: "existing-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    try sessionStore.save(existingSession)
    let service = makeSubscriptionService(sessionStore: sessionStore)

    service.recordSubscriptionPurchasePending()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertEqual(service.accessToken, "existing-token")
    XCTAssertEqual(sessionStore.loadValidSession(), existingSession)
  }

  func testSilentSubscriptionRecoveryCreatesBackendSessionWhenNoCachedSessionExists() async {
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        "signed-transaction"
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Silent recovery should not call AppStore.sync")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { request in
        XCTAssertEqual(request.signedTransactionInfo, "signed-transaction")
        XCTAssertEqual(request.installationId, configuration.installationId)
        return session
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(service.accessToken, "recovered-token")
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(sessionStore.loadValidSession(), session)
  }

  func testAccessTokenRecoveringIfNeededRefreshesStaleInMemorySession() async throws {
    var now = Date(timeIntervalSince1970: 1_000)
    let sessionStore = makeSessionStore(now: { now })
    try sessionStore.save(
      BackendSessionResponse(
        accessToken: "stale-token",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
      )
    )
    let recoveredSession = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        "signed-transaction"
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Stale token recovery during sync should not call AppStore.sync")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        recoveredSession
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    XCTAssertEqual(service.accessToken, "stale-token")

    now = Date(timeIntervalSince1970: 1_800)
    let accessToken = await service.accessTokenRecoveringIfNeeded()

    XCTAssertEqual(accessToken, "recovered-token")
    XCTAssertEqual(sessionStore.loadValidSession(), recoveredSession)
  }

  func testSilentSubscriptionRecoveryDoesNotPublishAlertStyleErrorWhenNoEntitlementExists() async {
    let diagnostics = makeDiagnostics()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      syncedCurrentEntitlementJWS: {
        XCTFail("Silent recovery should not call AppStore.sync")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("Backend should not be called without StoreKit entitlement")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics,
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertFalse(service.isSignedIn)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Connect to PumpSync or a self-hosted service")
    XCTAssertEqual(diagnostics.entries.first?.title, "Subscription recovery skipped")
    XCTAssertEqual(diagnostics.entries.first?.message, "No current StoreKit entitlement was available for subscription recovery.")
  }

  func testSelfHostedCreatesBackendSession() async {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://self-host.example/api"
    let sessionStore = makeSessionStore()

    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { request in
        XCTAssertEqual(request.installationId, configuration.installationId)
        return BackendSessionResponse(
          accessToken: "self-hosted-token",
          expiresAt: Date(timeIntervalSince1970: 1_800),
          serviceMode: "selfHosted",
          dataSourceMode: "tandemSource"
        )
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.connectSelfHosted()

    XCTAssertEqual(service.accessToken, "self-hosted-token")
    XCTAssertEqual(service.statusMessage, "Connected to self-hosted service")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "self-hosted-token")
  }

  func testSelfHostedBaseURLRequiresHttpsForNonLoopbackHosts() {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted

    configuration.selfHostedBaseURLString = "http://192.168.1.50:8080"
    XCTAssertNil(configuration.selectedBaseURL, "a plain-HTTP IP-literal self-host URL must be rejected")

    configuration.selfHostedBaseURLString = "http://backend.example.com"
    XCTAssertNil(configuration.selectedBaseURL, "a plain-HTTP hostname self-host URL must be rejected")

    configuration.selfHostedBaseURLString = "https://192.168.1.50:8080"
    XCTAssertNotNil(configuration.selectedBaseURL, "an HTTPS self-host URL must be accepted")
  }

  func testSelfHostedBaseURLAllowsHttpForLoopbackOnly() {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted

    configuration.selfHostedBaseURLString = "http://localhost:8080"
    XCTAssertNotNil(configuration.selectedBaseURL, "plain HTTP to localhost must be allowed for local development")

    configuration.selfHostedBaseURLString = "http://127.0.0.1:8080"
    XCTAssertNotNil(configuration.selectedBaseURL, "plain HTTP to 127.0.0.1 must be allowed for local development")
  }

  func testSelfHostedBaseURLRejectsMalformedOrEmptyInput() {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted

    configuration.selfHostedBaseURLString = ""
    XCTAssertNil(configuration.selectedBaseURL)

    configuration.selfHostedBaseURLString = "not a url"
    XCTAssertNil(configuration.selectedBaseURL)

    configuration.selfHostedBaseURLString = "ftp://backend.example.com"
    XCTAssertNil(configuration.selectedBaseURL, "non-http(s) schemes must be rejected")
  }

  func testConnectionChangeClearsCachedSession() throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    try sessionStore.save(
      BackendSessionResponse(
        accessToken: "cached-token",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
      )
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    service.clearSessionForConnectionChange()

    XCTAssertNil(sessionStore.loadValidSession())
    XCTAssertFalse(service.isSignedIn)
  }

  func testExpiredCachedSessionTriggersSubscriptionRecovery() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(
      BackendSessionResponse(
        accessToken: "expired-token",
        expiresAt: Date(timeIntervalSince1970: 1_999),
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
      )
    )
    let recoveredSession = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { _ in
        recoveredSession
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(service.accessToken, "recovered-token")
    XCTAssertEqual(sessionStore.loadValidSession(), recoveredSession)
  }

  func testBackgroundRecoveryRefreshesRenewableSessionWithoutStoreKit() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(BackendSessionResponse(
      accessToken: "expired-access-token",
      expiresAt: Date(timeIntervalSince1970: 1_999),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 2,
      sessionFamilyId: "family-1",
      refreshToken: "refresh-token-1",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_000),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    ))
    let refreshed = BackendSessionResponse(
      accessToken: "refreshed-access-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 2,
      sessionFamilyId: "family-2",
      refreshToken: "refresh-token-2",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_500),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    let responseData = try JSONCodec.encoder.encode(refreshed)
    URLProtocolStub.requestHandler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/session/refresh")
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, responseData)
    }
    defer { URLProtocolStub.requestHandler = nil }
    let apiClient = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )
    let service = AuthService(
      apiClient: apiClient,
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: {
        XCTFail("Background renewable-session recovery must not call StoreKit")
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        XCTFail("Background renewable-session recovery must not create a subscription session")
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )

    let token = await service.accessTokenRecoveringIfNeeded(allowInteractiveRecovery: false)

    XCTAssertEqual(token, "refreshed-access-token")
    XCTAssertEqual(sessionStore.loadValidSession(), refreshed)
  }

  func testSubscriptionConnectionRequiredMessageUsesSubscriptionTerminology() {
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      createSubscriptionSession: { _ in
        throw APIClientError.invalidResponse
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      proofProvider: AcceptingProofProvider()
    )

    let expected = "No PumpSync service was found. Please subscribe to PumpSync or set up your own self-hosted PumpSync service."
    XCTAssertEqual(service.connectionRequiredMessage, expected)
    XCTAssertEqual(StoreKitSubscriptionError.noActiveSubscription.errorDescription, expected)
  }

  private func makeAPIClient() -> PumpSyncAPIClient {
    PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )
  }

  private func makeConfigurationStore() -> BackendConfigurationStore {
    let defaults = UserDefaults(suiteName: "AuthServiceTests-\(UUID().uuidString)")!
    return BackendConfigurationStore(defaults: defaults)
  }

  private func makeSubscriptionService(sessionStore: BackendSessionStore) -> AuthService {
    AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: sessionStore,
      currentEntitlementJWS: { throw StoreKitSubscriptionError.noActiveSubscription },
      createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
      createSelfHostedSession: { _ in throw APIClientError.invalidResponse },
      proofProvider: AcceptingProofProvider()
    )
  }

  private func makeSessionStore(now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }) -> BackendSessionStore {
    BackendSessionStore(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      now: now
    )
  }

  private func makeDiagnostics() -> DiagnosticsLogStore {
    DiagnosticsLogStore(defaults: UserDefaults(suiteName: "AuthServiceTests-\(UUID().uuidString)")!)
  }

  private final class AcceptingProofProvider: DeviceSessionProofProviding {
    func hostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String,
      existingSession: BackendSessionResponse?
    ) async throws -> HostedDeviceEnrollment {
      HostedDeviceEnrollment(
        requestId: "request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        challengeToken: challenge.challengeToken,
        keyId: "app-attest-key",
        attestationObject: "attestation",
        assertion: nil
      )
    }

    func selfHostedEnrollment(
      challenge: SessionChallengeResponse,
      installationId: String
    ) throws -> SelfHostedDeviceEnrollment {
      SelfHostedDeviceEnrollment(
        requestId: "request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        challengeToken: challenge.challengeToken,
        publicKey: "public-key",
        signature: "signature"
      )
    }

    func refreshRequest(
      session: BackendSessionResponse,
      installationId: String,
      mode: BackendAccessMode
    ) async throws -> SessionRefreshRequest {
      SessionRefreshRequest(
        installationId: installationId,
        refreshToken: session.refreshToken,
        requestId: "request-1",
        issuedAt: Date(timeIntervalSince1970: 2_000),
        proof: "proof"
      )
    }
  }
}
