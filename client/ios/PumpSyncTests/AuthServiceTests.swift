import XCTest
@testable import PumpSync

@MainActor
final class AuthServiceTests: XCTestCase {
  func testLoadsValidCachedSessionWithoutCallingStoreKitOrBackend() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    let cachedSession = BackendSessionResponse(
      accessToken: "cached-token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      entitlementActive: true,
      serviceMode: "hosted"
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
      }
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(service.accessToken, "cached-token")
    XCTAssertTrue(service.isSignedIn)
  }

  func testHostedRestoreCreatesBackendSession() async {
    let diagnostics = DiagnosticsLogStore()
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      entitlementActive: true,
      serviceMode: "hosted"
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
      diagnostics: diagnostics
    )

    await service.connectHostedUsingCurrentSubscription()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Hosted subscription active")
    XCTAssertEqual(sessionStore.loadValidSession(), session)
    XCTAssertEqual(diagnostics.entries.map(\.title), ["Hosted subscription restored", "Hosted session started", "Hosted restore started"])
  }

  func testHostedPurchaseCompletionCreatesBackendSession() async {
    let diagnostics = DiagnosticsLogStore()
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      entitlementActive: true,
      serviceMode: "hosted"
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
      diagnostics: diagnostics
    )

    await service.activateHostedSubscription(signedTransactionInfo: "signed-purchase-transaction")

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Hosted subscription active")
    XCTAssertEqual(sessionStore.loadValidSession(), session)
    XCTAssertEqual(diagnostics.entries.map(\.title), ["Hosted subscription purchased", "Hosted session started"])
  }

  func testHostedRestorePublishesUserSafeErrorAndDiagnostics() async {
    let diagnostics = DiagnosticsLogStore()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      sessionStore: makeSessionStore(),
      currentEntitlementJWS: {
        "signed-transaction"
      },
      createSubscriptionSession: { _ in
        throw APIClientError.httpStatus(401, "Subscription validation failed for user@example.com.")
      },
      createSelfHostedSession: { _ in
        throw APIClientError.invalidResponse
      },
      diagnostics: diagnostics
    )

    await service.connectHostedUsingCurrentSubscription()

    let expectedMessage = "PumpSync could not verify your App Store subscription. Check your Apple Account subscription, then try Restore Subscription again."
    XCTAssertFalse(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertEqual(service.statusMessage, expectedMessage)
    XCTAssertEqual(service.errorMessage, expectedMessage)
    XCTAssertEqual(service.connectionRequiredMessage, expectedMessage)
    XCTAssertEqual(diagnostics.entries.first?.title, "Hosted session failed")
    XCTAssertEqual(diagnostics.entries.first?.message, "Subscription validation failed for [redacted email].")
  }

  func testSilentHostedRecoveryCreatesBackendSessionWhenNoCachedSessionExists() async {
    let configuration = makeConfigurationStore()
    let sessionStore = makeSessionStore()
    let session = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      entitlementActive: true,
      serviceMode: "hosted"
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
      }
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
        entitlementActive: true,
        serviceMode: "hosted"
      )
    )
    let recoveredSession = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      entitlementActive: true,
      serviceMode: "hosted"
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
      }
    )

    XCTAssertEqual(service.accessToken, "stale-token")

    now = Date(timeIntervalSince1970: 1_800)
    let accessToken = await service.accessTokenRecoveringIfNeeded()

    XCTAssertEqual(accessToken, "recovered-token")
    XCTAssertEqual(sessionStore.loadValidSession(), recoveredSession)
  }

  func testSilentHostedRecoveryDoesNotPublishAlertStyleErrorWhenNoEntitlementExists() async {
    let diagnostics = DiagnosticsLogStore()
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
      diagnostics: diagnostics
    )

    await service.recoverSessionIfNeeded()

    XCTAssertFalse(service.isSignedIn)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Connect to PumpSync or a self-hosted service")
    XCTAssertEqual(diagnostics.entries.first?.title, "Hosted recovery skipped")
    XCTAssertEqual(diagnostics.entries.first?.message, "No current StoreKit entitlement was available for hosted recovery.")
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
          entitlementActive: true,
          serviceMode: "selfHosted"
        )
      }
    )

    await service.connectSelfHosted()

    XCTAssertEqual(service.accessToken, "self-hosted-token")
    XCTAssertEqual(service.statusMessage, "Connected to self-hosted service")
    XCTAssertEqual(sessionStore.loadValidSession()?.accessToken, "self-hosted-token")
  }

  func testConnectionChangeClearsCachedSession() throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 1_000) })
    try sessionStore.save(
      BackendSessionResponse(
        accessToken: "cached-token",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        entitlementActive: true,
        serviceMode: "hosted"
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
      }
    )

    service.clearSessionForConnectionChange()

    XCTAssertNil(sessionStore.loadValidSession())
    XCTAssertFalse(service.isSignedIn)
  }

  func testExpiredCachedSessionTriggersHostedRecovery() async throws {
    let sessionStore = makeSessionStore(now: { Date(timeIntervalSince1970: 2_000) })
    try sessionStore.save(
      BackendSessionResponse(
        accessToken: "expired-token",
        expiresAt: Date(timeIntervalSince1970: 1_999),
        entitlementActive: true,
        serviceMode: "hosted"
      )
    )
    let recoveredSession = BackendSessionResponse(
      accessToken: "recovered-token",
      expiresAt: Date(timeIntervalSince1970: 3_000),
      entitlementActive: true,
      serviceMode: "hosted"
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
      }
    )

    await service.recoverSessionIfNeeded()

    XCTAssertEqual(service.accessToken, "recovered-token")
    XCTAssertEqual(sessionStore.loadValidSession(), recoveredSession)
  }

  func testHostedConnectionRequiredMessageUsesHostedServiceTerminology() {
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
      }
    )

    let expected = "No PumpSync service was found. Please subscribe to PumpSync or set up your own self-hosted PumpSync service."
    XCTAssertEqual(service.connectionRequiredMessage, expected)
    XCTAssertEqual(StoreKitSubscriptionError.noActiveSubscription.errorDescription, expected)
  }

  private func makeAPIClient() -> PumpSyncAPIClient {
    PumpSyncAPIClient(baseURL: URL(string: "https://example.com/api")!, urlSession: .shared, maxRetryCount: 0)
  }

  private func makeConfigurationStore() -> BackendConfigurationStore {
    let defaults = UserDefaults(suiteName: "AuthServiceTests-\(UUID().uuidString)")!
    return BackendConfigurationStore(defaults: defaults)
  }

  private func makeSessionStore(now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) }) -> BackendSessionStore {
    BackendSessionStore(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      now: now
    )
  }
}
