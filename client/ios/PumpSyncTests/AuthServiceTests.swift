import XCTest
@testable import PumpSync

@MainActor
final class AuthServiceTests: XCTestCase {
  func testHostedRestoreCreatesBackendSession() async {
    let diagnostics = DiagnosticsLogStore()
    let configuration = makeConfigurationStore()
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      entitlementActive: true,
      serviceMode: "hosted"
    )
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      currentEntitlementJWS: {
        "signed-transaction"
      },
      purchaseEntitlementJWS: {
        throw StoreKitSubscriptionError.productUnavailable
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
    XCTAssertEqual(service.statusMessage, "Hosted subscription active.")
    XCTAssertEqual(diagnostics.entries.map(\.title), ["Hosted subscription restored", "Hosted session started"])
  }

  func testHostedRestorePublishesSafeBackendErrorAndDiagnostics() async {
    let diagnostics = DiagnosticsLogStore()
    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: makeConfigurationStore(),
      currentEntitlementJWS: {
        "signed-transaction"
      },
      purchaseEntitlementJWS: {
        throw StoreKitSubscriptionError.productUnavailable
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

    XCTAssertFalse(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertEqual(service.statusMessage, "Subscription validation failed for [redacted email].")
    XCTAssertEqual(service.errorMessage, "Subscription validation failed for [redacted email].")
    XCTAssertEqual(diagnostics.entries.first?.title, "Hosted session failed")
    XCTAssertEqual(diagnostics.entries.first?.message, "Subscription validation failed for [redacted email].")
  }

  func testSelfHostedCreatesBackendSession() async {
    let configuration = makeConfigurationStore()
    configuration.mode = .selfHosted
    configuration.selfHostedBaseURLString = "https://self-host.example/api"

    let service = AuthService(
      apiClient: makeAPIClient(),
      configurationStore: configuration,
      currentEntitlementJWS: {
        throw StoreKitSubscriptionError.noActiveSubscription
      },
      purchaseEntitlementJWS: {
        throw StoreKitSubscriptionError.productUnavailable
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
    XCTAssertEqual(service.statusMessage, "Connected to self-hosted service.")
  }

  private func makeAPIClient() -> PumpSyncAPIClient {
    PumpSyncAPIClient(baseURL: URL(string: "https://example.com/api")!, urlSession: .shared, maxRetryCount: 0)
  }

  private func makeConfigurationStore() -> BackendConfigurationStore {
    let defaults = UserDefaults(suiteName: "AuthServiceTests-\(UUID().uuidString)")!
    return BackendConfigurationStore(defaults: defaults)
  }
}
