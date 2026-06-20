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
      return "PumpSync"
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
  private let createSubscriptionSession: @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse
  private let createSelfHostedSession: @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse

  private(set) var isConnecting = false
  private(set) var session: BackendSessionResponse?
  private(set) var statusMessage = "Connect to PumpSync or a self-hosted service"
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
    createSubscriptionSession: @escaping @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse,
    createSelfHostedSession: @escaping @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.diagnostics = diagnostics
    self.currentEntitlementJWS = currentEntitlementJWS
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

  var connectionRequiredMessage: String {
    if let errorMessage {
      return errorMessage
    }

    switch configurationStore.mode {
    case .hosted:
      return StoreKitSubscriptionError.noActiveSubscription.errorDescription ?? statusMessage
    case .selfHosted:
      return "Connect to a self-hosted service before validating credentials."
    }
  }

  func connectHostedUsingCurrentSubscription() async {
    _ = configurationStore.apply(to: apiClient)
    isConnecting = true
    errorMessage = nil
    statusMessage = "Checking hosted service..."
    diagnostics?.record(source: .auth, title: "Hosted restore started")

    do {
      let signedTransactionInfo = try await currentEntitlementJWS()
      await establishHostedSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Activating hosted service...",
        title: "Hosted subscription restored"
      )
    } catch {
      session = nil
      let message = safeMessage("Hosted subscription access could not be verified.", error: error)
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Hosted restore failed")
      isConnecting = false
    }
  }

  func activateHostedSubscription(signedTransactionInfo: String) async {
    await establishHostedSession(
      signedTransactionInfo: signedTransactionInfo,
      activityMessage: "Activating hosted service...",
      title: "Hosted subscription purchased"
    )
  }

  func recordHostedSubscriptionPurchaseCancelled() {
    session = nil
    errorMessage = nil
    statusMessage = "Subscription purchase cancelled."
    isConnecting = false
    diagnostics?.record(source: .auth, title: "Hosted subscription purchase cancelled")
  }

  func recordHostedSubscriptionPurchasePending() {
    session = nil
    errorMessage = nil
    statusMessage = "Subscription purchase is pending App Store approval."
    isConnecting = false
    diagnostics?.record(source: .auth, title: "Hosted subscription purchase pending")
  }

  func recordHostedSubscriptionPurchaseFailed(_ error: Error) {
    session = nil
    let message = safeMessage("Subscription purchase could not be completed.", error: error)
    errorMessage = message
    statusMessage = message
    isConnecting = false
    diagnostics?.record(error: error, source: .auth, title: "Hosted subscription purchase failed")
  }

  func connectSelfHosted() async {
    guard configurationStore.apply(to: apiClient) else {
      errorMessage = "Enter a valid self-hosted service URL."
      statusMessage = errorMessage ?? statusMessage
      return
    }

    isConnecting = true
    errorMessage = nil
    statusMessage = "Connecting to self-hosted service..."
    diagnostics?.record(source: .auth, title: "Self-hosted session started")

    do {
      session = try await createSelfHostedSession(SelfHostedSessionRequest(installationId: configurationStore.installationId))
      statusMessage = "Connected to self-hosted service"
      diagnostics?.record(source: .auth, title: "Self-hosted session created")
    } catch {
      session = nil
      let message = safeMessage("Self-hosted connection could not be established.", error: error)
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
    statusMessage = "Connection disconnected"
    diagnostics?.record(source: .auth, title: "Connection cleared")
  }

  private func establishHostedSession(
    signedTransactionInfo: String,
    activityMessage: String,
    title: String
  ) async {
    _ = configurationStore.apply(to: apiClient)
    isConnecting = true
    errorMessage = nil
    statusMessage = activityMessage
    diagnostics?.record(source: .auth, title: "Hosted session started")

    do {
      session = try await createSubscriptionSession(
        SubscriptionSessionRequest(
          signedTransactionInfo: signedTransactionInfo,
          installationId: configurationStore.installationId
        )
      )
      statusMessage = "Hosted subscription active"
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
      return "No active hosted service was found."
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

#if DEBUG
extension AuthService {
  func applyScreenshotSession(serviceMode: String) {
    session = BackendSessionResponse(
      accessToken: "screenshot-access-token",
      expiresAt: Date().addingTimeInterval(60 * 60),
      entitlementActive: true,
      serviceMode: serviceMode
    )
    statusMessage = serviceMode == "hosted" ? "Hosted subscription active" : "Connected to self-hosted service"
    errorMessage = nil
    isConnecting = false
  }
}
#endif
