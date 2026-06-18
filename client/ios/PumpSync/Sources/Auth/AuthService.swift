import Foundation
import Observation
import StoreKit

enum BackendAccessMode: String, CaseIterable, Identifiable {
  case hosted
  case selfHosted

  var id: String { rawValue }

  var title: String {
    switch self {
    case .hosted:
      return "Hosted"
    case .selfHosted:
      return "Self-hosted"
    }
  }
}

@MainActor
@Observable
final class BackendConfigurationStore {
  var mode: BackendAccessMode {
    didSet {
      defaults.set(mode.rawValue, forKey: Self.modeKey)
    }
  }

  var selfHostedBaseURLString: String {
    didSet {
      defaults.set(selfHostedBaseURLString, forKey: Self.selfHostedBaseURLKey)
    }
  }

  let installationId: String

  private let defaults: UserDefaults
  private static let modeKey = "backend.mode"
  private static let selfHostedBaseURLKey = "backend.selfHostedBaseURL"
  private static let installationIdKey = "backend.installationId"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let modeValue = defaults.string(forKey: Self.modeKey) ?? BackendAccessMode.hosted.rawValue
    mode = BackendAccessMode(rawValue: modeValue) ?? .hosted
    selfHostedBaseURLString = defaults.string(forKey: Self.selfHostedBaseURLKey) ?? ""

    if let storedInstallationId = defaults.string(forKey: Self.installationIdKey), !storedInstallationId.isEmpty {
      installationId = storedInstallationId
    } else {
      let newInstallationId = UUID().uuidString
      defaults.set(newInstallationId, forKey: Self.installationIdKey)
      installationId = newInstallationId
    }
  }

  var selectedBaseURL: URL? {
    switch mode {
    case .hosted:
      return AppConstants.defaultAPIBaseURL
    case .selfHosted:
      return URL(string: selfHostedBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  func apply(to apiClient: PumpSyncAPIClient) -> Bool {
    guard let selectedBaseURL else {
      return false
    }

    apiClient.updateBaseURL(selectedBaseURL)
    return true
  }
}

@MainActor
@Observable
final class AuthService {
  private let apiClient: PumpSyncAPIClient
  private let configurationStore: BackendConfigurationStore
  private let diagnostics: DiagnosticsLogStore?
  private let currentEntitlementJWS: @MainActor () async throws -> String
  private let purchaseEntitlementJWS: @MainActor () async throws -> String
  private let createSubscriptionSession: @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse
  private let createSelfHostedSession: @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse

  private(set) var isConnecting = false
  private(set) var session: BackendSessionResponse?
  private(set) var statusMessage = "Connect to PumpSync Hosted or a self-hosted backend."
  private(set) var errorMessage: String?

  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.diagnostics = diagnostics
    currentEntitlementJWS = {
      try await StoreKitSubscriptionProvider.currentEntitlementJWS(productId: AppConstants.hostedSubscriptionProductId)
    }
    purchaseEntitlementJWS = {
      try await StoreKitSubscriptionProvider.purchaseEntitlementJWS(productId: AppConstants.hostedSubscriptionProductId)
    }
    createSubscriptionSession = { request in
      try await apiClient.createSubscriptionSession(request)
    }
    createSelfHostedSession = { request in
      try await apiClient.createSelfHostedSession(request)
    }
  }

  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    currentEntitlementJWS: @escaping @MainActor () async throws -> String,
    purchaseEntitlementJWS: @escaping @MainActor () async throws -> String,
    createSubscriptionSession: @escaping @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse,
    createSelfHostedSession: @escaping @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.diagnostics = diagnostics
    self.currentEntitlementJWS = currentEntitlementJWS
    self.purchaseEntitlementJWS = purchaseEntitlementJWS
    self.createSubscriptionSession = createSubscriptionSession
    self.createSelfHostedSession = createSelfHostedSession
  }

  var isSignedIn: Bool {
    session?.accessToken.isEmpty == false
  }

  var isSigningIn: Bool {
    isConnecting
  }

  var accessToken: String? {
    session?.accessToken
  }

  func connectHostedUsingCurrentSubscription() async {
    await establishHostedSession(transactionJWS: currentEntitlementJWS, title: "Hosted subscription restored")
  }

  func purchaseHostedSubscription() async {
    await establishHostedSession(transactionJWS: purchaseEntitlementJWS, title: "Hosted subscription purchased")
  }

  func connectSelfHosted() async {
    guard configurationStore.apply(to: apiClient) else {
      errorMessage = "Enter a valid self-hosted backend URL."
      statusMessage = errorMessage ?? statusMessage
      return
    }

    isConnecting = true
    errorMessage = nil
    statusMessage = "Connecting to self-hosted backend..."
    diagnostics?.record(source: .auth, title: "Self-hosted session started")

    do {
      session = try await createSelfHostedSession(SelfHostedSessionRequest(installationId: configurationStore.installationId))
      statusMessage = "Connected to self-hosted backend."
      diagnostics?.record(source: .auth, title: "Self-hosted session created")
    } catch {
      session = nil
      let message = safeMessage("Self-hosted backend access could not be established.", error: error)
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Self-hosted session failed")
    }

    isConnecting = false
  }

  func signIn() async {
    switch configurationStore.mode {
    case .hosted:
      await connectHostedUsingCurrentSubscription()
    case .selfHosted:
      await connectSelfHosted()
    }
  }

  func signOut() {
    session = nil
    errorMessage = nil
    statusMessage = "Backend access disconnected."
    diagnostics?.record(source: .auth, title: "Backend session cleared")
  }

  private func establishHostedSession(
    transactionJWS: @MainActor () async throws -> String,
    title: String
  ) async {
    _ = configurationStore.apply(to: apiClient)
    isConnecting = true
    errorMessage = nil
    statusMessage = "Checking hosted subscription..."
    diagnostics?.record(source: .auth, title: "Hosted session started")

    do {
      let jws = try await transactionJWS()
      session = try await createSubscriptionSession(
        SubscriptionSessionRequest(
          signedTransactionInfo: jws,
          installationId: configurationStore.installationId
        )
      )
      statusMessage = "Hosted subscription active."
      diagnostics?.record(source: .auth, title: title)
    } catch {
      session = nil
      let message = safeMessage("Hosted subscription access could not be verified.", error: error)
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Hosted session failed")
    }

    isConnecting = false
  }

  private func safeMessage(_ fallback: String, error: Error) -> String {
    guard let localizedError = error as? LocalizedError, let description = localizedError.errorDescription else {
      return fallback
    }

    return DiagnosticsLogStore.redacted(description)
  }
}

enum StoreKitSubscriptionError: LocalizedError {
  case productUnavailable
  case noActiveSubscription
  case unverifiedTransaction
  case purchaseCancelled
  case purchasePending

  var errorDescription: String? {
    switch self {
    case .productUnavailable:
      return "The hosted subscription is not available from the App Store."
    case .noActiveSubscription:
      return "No active hosted subscription was found."
    case .unverifiedTransaction:
      return "The App Store transaction could not be verified on this device."
    case .purchaseCancelled:
      return "The subscription purchase was cancelled."
    case .purchasePending:
      return "The subscription purchase is pending App Store approval."
    }
  }
}

private enum StoreKitSubscriptionProvider {
  static func purchaseEntitlementJWS(productId: String) async throws -> String {
    let products = try await Product.products(for: [productId])
    guard let product = products.first else {
      throw StoreKitSubscriptionError.productUnavailable
    }

    let result = try await product.purchase()
    switch result {
    case .success(let verificationResult):
      let transaction = try verified(verificationResult)
      let jwsRepresentation = verificationResult.jwsRepresentation
      await transaction.finish()
      return jwsRepresentation
    case .userCancelled:
      throw StoreKitSubscriptionError.purchaseCancelled
    case .pending:
      throw StoreKitSubscriptionError.purchasePending
    @unknown default:
      throw StoreKitSubscriptionError.unverifiedTransaction
    }
  }

  static func currentEntitlementJWS(productId: String) async throws -> String {
    try? await AppStore.sync()

    for await result in Transaction.currentEntitlements {
      let transaction = try verified(result)
      guard transaction.productID == productId else {
        continue
      }

      return result.jwsRepresentation
    }

    throw StoreKitSubscriptionError.noActiveSubscription
  }

  private static func verified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let value):
      return value
    case .unverified:
      throw StoreKitSubscriptionError.unverifiedTransaction
    }
  }
}
