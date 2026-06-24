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
  private let sessionStore: BackendSessionStore?
  private let diagnostics: DiagnosticsLogStore?
  private let currentEntitlementJWS: @MainActor () async throws -> String
  private let syncedCurrentEntitlementJWS: @MainActor () async throws -> String
  private let createSubscriptionSession: @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse
  private let createSelfHostedSession: @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse

  private(set) var isConnecting = false
  private(set) var session: BackendSessionResponse?
  private(set) var statusMessage = "Connect to PumpSync or a self-hosted service"
  private(set) var errorMessage: String?

  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    sessionStore: BackendSessionStore? = nil,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.sessionStore = sessionStore
    self.diagnostics = diagnostics
    currentEntitlementJWS = {
      try await StoreKitSubscriptionProvider.currentEntitlementJWS(
        productId: AppConstants.hostedSubscriptionProductId,
        syncWithAppStore: false
      )
    }
    syncedCurrentEntitlementJWS = {
      try await StoreKitSubscriptionProvider.currentEntitlementJWS(
        productId: AppConstants.hostedSubscriptionProductId,
        syncWithAppStore: true
      )
    }
    createSubscriptionSession = { request in
      try await apiClient.createSubscriptionSession(request)
    }
    createSelfHostedSession = { request in
      try await apiClient.createSelfHostedSession(request)
    }
    session = sessionStore?.loadValidSession()
  }

  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    sessionStore: BackendSessionStore? = nil,
    currentEntitlementJWS: @escaping @MainActor () async throws -> String,
    syncedCurrentEntitlementJWS: (@MainActor () async throws -> String)? = nil,
    createSubscriptionSession: @escaping @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse,
    createSelfHostedSession: @escaping @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.sessionStore = sessionStore
    self.diagnostics = diagnostics
    self.currentEntitlementJWS = currentEntitlementJWS
    self.syncedCurrentEntitlementJWS = syncedCurrentEntitlementJWS ?? currentEntitlementJWS
    self.createSubscriptionSession = createSubscriptionSession
    self.createSelfHostedSession = createSelfHostedSession
    session = sessionStore?.loadValidSession()
  }

  var isSignedIn: Bool {
    guard let session else {
      return false
    }

    if let sessionStore {
      return sessionStore.isValid(session)
    }

    return !session.accessToken.isEmpty
  }

  var isSigningIn: Bool {
    isConnecting
  }

  var accessToken: String? {
    guard isSignedIn else {
      return nil
    }

    return session?.accessToken
  }

  func accessTokenRecoveringIfNeeded() async -> String? {
    await recoverSessionIfNeeded()
    return accessToken
  }

  var connectionRequiredMessage: String {
    if let errorMessage {
      return hostedConnectionMessage(for: errorMessage)
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
      let signedTransactionInfo = try await syncedCurrentEntitlementJWS()
      await establishHostedSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Activating hosted service...",
        title: "Hosted subscription restored",
        publishesErrors: true
      )
    } catch StoreKitSubscriptionError.noActiveSubscription {
      session = nil
      try? sessionStore?.delete()
      let message = hostedConnectionMessage(for: StoreKitSubscriptionError.noActiveSubscription.errorDescription ?? "No active subscription was found.")
      errorMessage = message
      statusMessage = message
      diagnostics?.record(
        source: .auth,
        severity: .error,
        title: "Hosted restore failed",
        message: "No current StoreKit entitlement was available for hosted restore."
      )
      isConnecting = false
    } catch {
      session = nil
      try? sessionStore?.delete()
      let message = hostedConnectionMessage(for: safeMessage("Hosted subscription access could not be verified.", error: error))
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
      title: "Hosted subscription purchased",
      publishesErrors: true
    )
  }

  func recordHostedSubscriptionPurchaseCancelled() {
    session = nil
    try? sessionStore?.delete()
    errorMessage = nil
    statusMessage = "Subscription purchase cancelled."
    isConnecting = false
    diagnostics?.record(source: .auth, title: "Hosted subscription purchase cancelled")
  }

  func recordHostedSubscriptionPurchasePending() {
    session = nil
    try? sessionStore?.delete()
    errorMessage = nil
    statusMessage = "Subscription purchase is pending App Store approval."
    isConnecting = false
    diagnostics?.record(source: .auth, title: "Hosted subscription purchase pending")
  }

  func recordHostedSubscriptionPurchaseFailed(_ error: Error) {
    session = nil
    try? sessionStore?.delete()
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
      if let session {
        try? sessionStore?.save(session)
      }
      statusMessage = "Connected to self-hosted service"
      diagnostics?.record(source: .auth, title: "Self-hosted session created")
    } catch {
      session = nil
      try? sessionStore?.delete()
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

  func recoverSessionIfNeeded() async {
    guard !isConnecting else {
      return
    }

    if let session, sessionStore?.isValid(session) ?? !session.accessToken.isEmpty {
      return
    }

    if let restoredSession = sessionStore?.loadValidSession() {
      session = restoredSession
      errorMessage = nil
      statusMessage = restoredSession.serviceMode == "selfHosted" ? "Connected to self-hosted service" : "Hosted subscription active"
      diagnostics?.record(source: .auth, title: "Connection session restored")
      return
    }

    session = nil

    switch configurationStore.mode {
    case .hosted:
      await recoverHostedSession()
    case .selfHosted:
      await recoverSelfHostedSession()
    }
  }

  func clearSessionForConnectionChange() {
    session = nil
    try? sessionStore?.delete()
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
    diagnostics?.record(source: .auth, title: "Connection session reset")
  }

  func clearSessionForAuthenticationFailure() {
    session = nil
    try? sessionStore?.delete()
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
    diagnostics?.record(source: .auth, severity: .warning, title: "Connection session expired")
  }

  private func establishHostedSession(
    signedTransactionInfo: String,
    activityMessage: String,
    title: String,
    publishesErrors: Bool
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
      if let session {
        try? sessionStore?.save(session)
      }
      statusMessage = "Hosted subscription active"
      diagnostics?.record(source: .auth, title: title)
    } catch {
      session = nil
      try? sessionStore?.delete()
      if publishesErrors {
        let message = hostedConnectionMessage(for: safeMessage("Hosted subscription access could not be verified.", error: error))
        errorMessage = message
        statusMessage = message
      } else {
        resetDisconnectedStatus()
      }
      diagnostics?.record(error: error, source: .auth, title: "Hosted session failed")
    }

    isConnecting = false
  }

  private func recoverHostedSession() async {
    diagnostics?.record(source: .auth, title: "Hosted recovery started")

    do {
      let signedTransactionInfo = try await currentEntitlementJWS()
      await establishHostedSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Restoring hosted service...",
        title: "Hosted subscription recovered",
        publishesErrors: false
      )
    } catch StoreKitSubscriptionError.noActiveSubscription {
      session = nil
      try? sessionStore?.delete()
      resetDisconnectedStatus()
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Hosted recovery skipped",
        message: "No current StoreKit entitlement was available for hosted recovery."
      )
    } catch {
      session = nil
      try? sessionStore?.delete()
      resetDisconnectedStatus()
      diagnostics?.record(error: error, source: .auth, title: "Hosted recovery failed")
    }
  }

  private func recoverSelfHostedSession() async {
    guard configurationStore.apply(to: apiClient) else {
      diagnostics?.record(source: .auth, severity: .warning, title: "Self-hosted recovery skipped", message: "No valid self-hosted service URL is configured.")
      return
    }

    isConnecting = true
    errorMessage = nil
    statusMessage = "Connecting to self-hosted service..."
    diagnostics?.record(source: .auth, title: "Self-hosted recovery started")

    do {
      session = try await createSelfHostedSession(SelfHostedSessionRequest(installationId: configurationStore.installationId))
      if let session {
        try? sessionStore?.save(session)
      }
      statusMessage = "Connected to self-hosted service"
      diagnostics?.record(source: .auth, title: "Self-hosted session recovered")
    } catch {
      session = nil
      try? sessionStore?.delete()
      resetDisconnectedStatus()
      diagnostics?.record(error: error, source: .auth, title: "Self-hosted recovery failed")
    }

    isConnecting = false
  }

  private func resetDisconnectedStatus() {
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
  }

  private func safeMessage(_ fallback: String, error: Error) -> String {
    guard let localizedError = error as? LocalizedError, let description = localizedError.errorDescription else {
      return fallback
    }

    return DiagnosticsLogStore.redacted(description)
  }

  private func hostedConnectionMessage(for message: String) -> String {
    switch configurationStore.mode {
    case .hosted:
      return "PumpSync could not verify your App Store subscription. Check your Apple Account subscription, then try Restore purchases again."
    case .selfHosted:
      return message
    }
  }
}

enum StoreKitSubscriptionError: LocalizedError {
  case productUnavailable
  case noActiveSubscription
  case inactiveSubscriptionTransaction
  case subscriptionManagementUnavailable
  case unverifiedTransaction
  case purchaseCancelled
  case purchasePending

  var errorDescription: String? {
    switch self {
    case .productUnavailable:
      return "The hosted subscription is not available from the App Store."
    case .noActiveSubscription:
      return "No PumpSync service was found. Please subscribe to PumpSync or set up your own self-hosted PumpSync service."
    case .inactiveSubscriptionTransaction:
      return "The App Store returned an inactive subscription transaction. Try subscribing again, or use a fresh sandbox tester if you recently reset purchase history."
    case .subscriptionManagementUnavailable:
      return "Apple subscription management is not available right now."
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
  static func currentEntitlementJWS(productId: String, syncWithAppStore: Bool) async throws -> String {
    if syncWithAppStore {
      try? await AppStore.sync()
    }

    for await result in Transaction.currentEntitlements {
      let transaction = try verified(result)
      guard transaction.productID == productId else {
        continue
      }

      guard transaction.isActiveSubscriptionEntitlement else {
        await transaction.finish()
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

extension Transaction {
  var isActiveSubscriptionEntitlement: Bool {
    if revocationDate != nil {
      return false
    }

    if let expirationDate, expirationDate <= Date() {
      return false
    }

    return true
  }

  func diagnosticSummary(active: Bool) -> String {
    [
      "productID=\(productID)",
      "id=\(id)",
      "originalID=\(originalID)",
      "purchaseDate=\(purchaseDate.storeKitDiagnosticDate)",
      "expirationDate=\(expirationDate?.storeKitDiagnosticDate ?? "none")",
      "revocationDate=\(revocationDate?.storeKitDiagnosticDate ?? "none")",
      "active=\(active)"
    ].joined(separator: ", ")
  }
}

private extension Date {
  var storeKitDiagnosticDate: String {
    formatted(date: .abbreviated, time: .standard)
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
