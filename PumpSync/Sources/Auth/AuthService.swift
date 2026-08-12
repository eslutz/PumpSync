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
  nonisolated static let installationIdDefaultsKey = "backend.installationId"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let modeValue = defaults.string(forKey: Self.modeKey) ?? BackendAccessMode.hosted.rawValue
    mode = BackendAccessMode(rawValue: modeValue) ?? .hosted
    selfHostedBaseURLString = defaults.string(forKey: Self.selfHostedBaseURLKey) ?? ""

    if let storedInstallationId = defaults.string(forKey: Self.installationIdDefaultsKey), !storedInstallationId.isEmpty {
      installationId = storedInstallationId
    } else {
      let newInstallationId = UUID().uuidString
      defaults.set(newInstallationId, forKey: Self.installationIdDefaultsKey)
      installationId = newInstallationId
    }
  }

  var selectedBaseURL: URL? {
    switch mode {
    case .hosted:
      return AppConstants.defaultAPIBaseURL
    case .selfHosted:
      return Self.validatedSelfHostedURL(from: selfHostedBaseURLString)
    }
  }

  /// ATS does not block cleartext HTTP to IP-address literals or unqualified
  /// hostnames — exactly what a self-hosted URL typically looks like — so this
  /// requires HTTPS explicitly rather than relying on ATS alone. Loopback is
  /// allowed over HTTP for local development against a backend run on the
  /// same machine.
  private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

  private static func validatedSelfHostedURL(from rawValue: String) -> URL? {
    guard
      let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
      let scheme = url.scheme?.lowercased(),
      let host = url.host,
      !host.isEmpty
    else {
      return nil
    }

    if scheme == "https" {
      return url
    }

    if scheme == "http" && loopbackHosts.contains(host.lowercased()) {
      return url
    }

    return nil
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
  private let subscriptionSessionTimeout: TimeInterval

  private(set) var isConnecting = false
  private(set) var session: BackendSessionResponse?
  private(set) var statusMessage = "Connect to PumpSync or a self-hosted service"
  private(set) var errorMessage: String?
  private var transactionUpdatesTask: Task<Void, Never>?
  private var subscriptionOperationTask: Task<Void, Never>?

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
    subscriptionSessionTimeout = 20
    currentEntitlementJWS = {
      try await StoreKitSubscriptionProvider.currentEntitlementJWS(
        productId: AppConstants.subscriptionProductId,
        syncWithAppStore: false
      )
    }
    syncedCurrentEntitlementJWS = {
      try await StoreKitSubscriptionProvider.currentEntitlementJWS(
        productId: AppConstants.subscriptionProductId,
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
    diagnostics: DiagnosticsLogStore? = nil,
    subscriptionSessionTimeout: TimeInterval = 20
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.sessionStore = sessionStore
    self.diagnostics = diagnostics
    self.subscriptionSessionTimeout = subscriptionSessionTimeout
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
      return subscriptionConnectionMessage(for: errorMessage)
    }

    switch configurationStore.mode {
    case .hosted:
      return StoreKitSubscriptionError.noActiveSubscription.errorDescription ?? statusMessage
    case .selfHosted:
      return "Connect to a self-hosted service before validating credentials."
    }
  }

  func connectUsingCurrentSubscription() async {
    await runCoalescedSubscriptionOperation {
      await self.restoreCurrentSubscription()
    }
  }

  private func restoreCurrentSubscription() async {
    _ = configurationStore.apply(to: apiClient)
    isConnecting = true
    errorMessage = nil
    statusMessage = "Checking Subscription…"
    diagnostics?.record(source: .auth, title: "Subscription restore started")

    do {
      let signedTransactionInfo = try await syncedCurrentEntitlementJWS()
      await establishSubscriptionSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Connecting to PumpSync…",
        title: "PumpSync subscription restored",
        publishesErrors: true
      )
    } catch StoreKitSubscriptionError.noActiveSubscription {
      preserveValidSessionOrClear()
      let message = subscriptionConnectionMessage(for: StoreKitSubscriptionError.noActiveSubscription.errorDescription ?? "No active subscription was found.")
      errorMessage = message
      statusMessage = message
      diagnostics?.record(
        source: .auth,
        severity: .error,
        title: "Subscription restore failed",
        message: "No current StoreKit entitlement was available for subscription restore."
      )
      isConnecting = false
    } catch {
      preserveValidSessionOrClear()
      let message = subscriptionConnectionMessage(for: safeMessage("PumpSync subscription access could not be verified.", error: error))
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Subscription restore failed")
      isConnecting = false
    }
  }

  func activateSubscription(signedTransactionInfo: String) async {
    await runCoalescedSubscriptionOperation {
      await self.establishSubscriptionSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Connecting to PumpSync…",
        title: "PumpSync subscription purchased",
        publishesErrors: true
      )
    }
  }

  /// Starts listening for StoreKit transaction updates that arrive outside the
  /// purchase sheet: Ask-to-Buy approvals, renewals after a billing retry, and
  /// refunds/revocations. Without this, those transactions are never observed
  /// or finished, and StoreKit keeps redelivering them on every launch.
  func startObservingTransactionUpdates() {
    guard transactionUpdatesTask == nil else {
      return
    }

    transactionUpdatesTask = Task { [weak self] in
      for await result in Transaction.updates {
        await self?.handleTransactionUpdate(result)
      }
    }
  }

  func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
    guard case .verified(let transaction) = result else {
      diagnostics?.record(source: .auth, severity: .warning, title: "Unverified subscription transaction update ignored")
      return
    }

    guard transaction.productID == AppConstants.subscriptionProductId else {
      await transaction.finish()
      return
    }

    // These updates can arrive at any time, independent of which connection
    // mode is currently selected. Acting on a hosted transaction while
    // self-hosted mode is active would apply the self-hosted base URL,
    // then post a hosted-session request there — at best a wasted/rejected
    // request, at worst overwriting the self-hosted session with a
    // mismatched one if that URL happens to accept it. Only hosted mode
    // should ever be touched by these updates.
    guard configurationStore.mode == .hosted else {
      diagnostics?.record(
        source: .auth,
        title: "PumpSync subscription transaction update skipped",
        message: "Self-hosted mode is active; not touching the current session. \(transaction.diagnosticSummary(active: transaction.isActiveSubscriptionEntitlement))"
      )
      await transaction.finish()
      return
    }

    if transaction.isActiveSubscriptionEntitlement {
      await transaction.finish()
      await activateSubscription(signedTransactionInfo: result.jwsRepresentation)
    } else if session != nil {
      // Guarded on session != nil: the first time an app observes
      // Transaction.updates, StoreKit replays every transaction that's
      // never been finish()ed, not just new ones — for a long-running
      // sandbox tester (5-minute renewal cycles), that can be hundreds of
      // historical, already-superseded transactions delivered in a burst.
      // Without this guard, each one redundantly cleared a session that
      // was either already nil or about to be re-set by a later, more
      // current transaction later in the same burst — flooding the
      // diagnostics log and briefly leaving the app looking disconnected
      // mid-replay. Only the transition from "had a session" to "don't
      // anymore" is actually informative.
      session = nil
      try? sessionStore?.delete()
      errorMessage = nil
      statusMessage = "Connect to PumpSync or a self-hosted service"
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "PumpSync subscription revoked or expired",
        message: transaction.diagnosticSummary(active: false)
      )
    }

    if !transaction.isActiveSubscriptionEntitlement {
      await transaction.finish()
    }
  }

  func recordSubscriptionPurchaseCancelled() {
    preserveValidSessionOrClear()
    errorMessage = nil
    statusMessage = "Subscription purchase cancelled."
    isConnecting = false
    diagnostics?.record(source: .auth, title: "PumpSync subscription purchase cancelled")
  }

  func recordSubscriptionPurchasePending() {
    preserveValidSessionOrClear()
    errorMessage = nil
    statusMessage = "Subscription purchase is pending App Store approval."
    isConnecting = false
    diagnostics?.record(source: .auth, title: "PumpSync subscription purchase pending")
  }

  func recordSubscriptionPurchaseFailed(_ error: Error) {
    preserveValidSessionOrClear()
    let message = safeMessage("Subscription purchase could not be completed.", error: error)
    errorMessage = message
    statusMessage = message
    isConnecting = false
    diagnostics?.record(error: error, source: .auth, title: "PumpSync subscription purchase failed")
  }

  func connectSelfHosted() async {
    guard configurationStore.apply(to: apiClient) else {
      errorMessage = "Enter a valid self-hosted service URL starting with https:// (http:// is only allowed for localhost)."
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
        recordDemoModeIfNeeded(session)
      }
      statusMessage = session.map(Self.connectedStatusMessage(for:)) ?? "Connected to self-hosted service"
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

  func recoverSessionIfNeeded() async {
    if let session, sessionStore?.isValid(session) ?? !session.accessToken.isEmpty {
      diagnostics?.record(source: .auth, title: "Connection session cache hit", message: "cacheHit=true totalMs=0")
      return
    }

    if let restoredSession = sessionStore?.loadValidSession() {
      session = restoredSession
      errorMessage = nil
      statusMessage = Self.connectedStatusMessage(for: restoredSession)
      diagnostics?.record(source: .auth, title: "Connection session restored")
      return
    }

    session = nil

    switch configurationStore.mode {
    case .hosted:
      await runCoalescedSubscriptionOperation {
        await self.recoverSubscriptionSession()
      }
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

  private func establishSubscriptionSession(
    signedTransactionInfo: String,
    activityMessage: String,
    title: String,
    publishesErrors: Bool
  ) async {
    _ = configurationStore.apply(to: apiClient)
    let previousSession = session
    let hasValidPreviousSession = previousSession.map { sessionStore?.isValid($0) ?? !$0.accessToken.isEmpty } ?? false
    isConnecting = true
    errorMessage = nil
    statusMessage = activityMessage
    diagnostics?.record(source: .auth, title: "Subscription session started")

    let backendStartedAt = Date()
    var timedOut = false
    do {
      session = try await createSubscriptionSessionWithTimeout(
        SubscriptionSessionRequest(
          signedTransactionInfo: signedTransactionInfo,
          installationId: configurationStore.installationId
        )
      )
      if let session {
        try? sessionStore?.save(session)
      }
      statusMessage = "PumpSync subscription active"
      diagnostics?.record(source: .auth, title: title)
    } catch {
      timedOut = error is SubscriptionSessionTimeoutError
      if hasValidPreviousSession {
        session = previousSession
      } else {
        session = nil
        try? sessionStore?.delete()
      }
      if publishesErrors {
        let message = subscriptionConnectionMessage(for: safeMessage("PumpSync subscription access could not be verified.", error: error))
        errorMessage = message
        statusMessage = message
      } else {
        if hasValidPreviousSession, let previousSession {
          statusMessage = Self.connectedStatusMessage(for: previousSession)
        } else {
          resetDisconnectedStatus()
        }
      }
      diagnostics?.record(error: error, source: .auth, title: "Subscription session failed")
    }

    let backendMs = Int(Date().timeIntervalSince(backendStartedAt) * 1_000)
    diagnostics?.record(
      source: .auth,
      severity: timedOut ? .warning : .info,
      title: "Subscription session timing",
      message: "backendMs=\(backendMs) timedOut=\(timedOut) cacheHit=false"
    )

    isConnecting = false
  }

  private func recoverSubscriptionSession() async {
    let startedAt = Date()
    diagnostics?.record(source: .auth, title: "Subscription recovery started")

    do {
      let entitlementStartedAt = Date()
      let signedTransactionInfo = try await currentEntitlementJWS()
      let entitlementMs = Int(Date().timeIntervalSince(entitlementStartedAt) * 1_000)
      await establishSubscriptionSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Connecting to PumpSync…",
        title: "PumpSync subscription recovered",
        publishesErrors: false
      )
      diagnostics?.record(source: .auth, title: "Subscription recovery timing", message: "entitlementMs=\(entitlementMs) totalMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) cacheHit=false")
    } catch StoreKitSubscriptionError.noActiveSubscription {
      session = nil
      try? sessionStore?.delete()
      resetDisconnectedStatus()
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Subscription recovery skipped",
        message: "No current StoreKit entitlement was available for subscription recovery."
      )
    } catch {
      session = nil
      try? sessionStore?.delete()
      resetDisconnectedStatus()
      diagnostics?.record(error: error, source: .auth, title: "Subscription recovery failed")
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
        recordDemoModeIfNeeded(session)
      }
      statusMessage = session.map(Self.connectedStatusMessage(for:)) ?? "Connected to self-hosted service"
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

  private func runCoalescedSubscriptionOperation(_ operation: @escaping @MainActor () async -> Void) async {
    if let subscriptionOperationTask {
      diagnostics?.record(source: .auth, title: "Subscription operation coalesced", message: "coalesced=true")
      await subscriptionOperationTask.value
      return
    }

    let task = Task { @MainActor in
      await operation()
    }
    subscriptionOperationTask = task
    await task.value
    subscriptionOperationTask = nil
  }

  private func createSubscriptionSessionWithTimeout(
    _ request: SubscriptionSessionRequest
  ) async throws -> BackendSessionResponse {
    try await withCheckedThrowingContinuation { continuation in
      var hasResumed = false

      Task { @MainActor in
        do {
          let response = try await createSubscriptionSession(request)
          guard !hasResumed else { return }
          hasResumed = true
          continuation.resume(returning: response)
        } catch {
          guard !hasResumed else { return }
          hasResumed = true
          continuation.resume(throwing: error)
        }
      }

      Task { @MainActor in
        try? await Task.sleep(for: .seconds(subscriptionSessionTimeout))
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(throwing: SubscriptionSessionTimeoutError())
      }
    }
  }

  private func preserveValidSessionOrClear() {
    if let session, sessionStore?.isValid(session) ?? !session.accessToken.isEmpty {
      return
    }
    session = nil
    try? sessionStore?.delete()
  }

  /// The backend reports its data source on the session so a user who points
  /// the app at a demo deployment can tell before fabricated insulin/carb
  /// samples are written into their real Apple Health store.
  static func connectedStatusMessage(for session: BackendSessionResponse) -> String {
    guard session.serviceMode == "selfHosted" else {
      return "PumpSync subscription active"
    }

    return session.isSyntheticDemo
      ? "Connected to a demo service — data is synthetic, not from your pump"
      : "Connected to self-hosted service"
  }

  private func recordDemoModeIfNeeded(_ session: BackendSessionResponse) {
    guard session.isSyntheticDemo else {
      return
    }

    diagnostics?.record(
      source: .auth,
      severity: .warning,
      title: "Connected to a synthetic demo backend",
      message: "This service returns deterministic demo data; samples written to Apple Health will not reflect the pump."
    )
  }

  private func safeMessage(_ fallback: String, error: Error) -> String {
    guard let localizedError = error as? LocalizedError, let description = localizedError.errorDescription else {
      return fallback
    }

    return DiagnosticsLogStore.redacted(description)
  }

  private func subscriptionConnectionMessage(for message: String) -> String {
    switch configurationStore.mode {
    case .hosted:
      return "PumpSync could not verify your App Store subscription. Check your Apple Account subscription, then try Restore Subscription again."
    case .selfHosted:
      return message
    }
  }
}

private struct SubscriptionSessionTimeoutError: LocalizedError {
  var errorDescription: String? { "Connecting to PumpSync timed out. Please try again." }
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
      return "The PumpSync subscription is not available from the App Store."
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

      await transaction.finish()
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

  /// Transaction identifiers are truncated: the full values are pseudonymous
  /// purchase identifiers that persist into the diagnostics log, support
  /// bundle, and clipboard — the suffix is enough to correlate entries
  /// without handing the complete identifier to support channels.
  func diagnosticSummary(active: Bool) -> String {
    [
      "productID=\(productID)",
      "id=…\(String(String(id).suffix(4)))",
      "originalID=…\(String(String(originalID).suffix(4)))",
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
      serviceMode: serviceMode,
      dataSourceMode: "tandemSource"
    )
    statusMessage = serviceMode == "hosted" ? "PumpSync subscription active" : "Connected to self-hosted service"
    errorMessage = nil
    isConnecting = false
  }
}
#endif
