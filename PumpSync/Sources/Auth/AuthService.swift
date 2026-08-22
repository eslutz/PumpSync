import CryptoKit
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
      if mode != oldValue {
        revision &+= 1
      }
    }
  }

  var selfHostedBaseURLString: String {
    didSet {
      defaults.set(selfHostedBaseURLString, forKey: Self.selfHostedBaseURLKey)
      if selfHostedBaseURLString != oldValue {
        revision &+= 1
      }
    }
  }

  let installationId: String
  private(set) var revision = 0

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
  private let proofProvider: DeviceSessionProofProviding
  private let diagnostics: DiagnosticsLogStore?
  private let currentEntitlementJWS: @MainActor () async throws -> String
  private let syncedCurrentEntitlementJWS: @MainActor () async throws -> String
  private let createSubscriptionSession: @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse
  private let createSelfHostedSession: @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse
  private let createSessionChallenge: @MainActor (SessionChallengeRequest) async throws -> SessionChallengeResponse
  private let warmupHostedService: @MainActor () async throws -> Void
  private let subscriptionSessionTimeout: TimeInterval

  private(set) var isConnecting = false
  private(set) var session: BackendSessionResponse?
  private(set) var statusMessage = "Connect to PumpSync or a self-hosted service"
  private(set) var errorMessage: String?
  private var transactionUpdatesTask: Task<Void, Never>?
  private var subscriptionOperationTask: Task<Void, Never>?
  private var subscriptionOperationID: UUID?
  private struct RenewableRefreshOperationKey: Equatable {
    let configurationRevision: Int
    let mode: BackendAccessMode
    let sessionFamilyId: String
  }
  private var renewableRefreshTask: Task<Bool, Never>?
  private var renewableRefreshOperationID: UUID?
  private var renewableRefreshOperationKey: RenewableRefreshOperationKey?
  private var selfHostedOperationID: UUID?
  // Process-local by design: explicit purchase/restore actions may retry the
  // same JWS, while StoreKit's automatic update stream must not replay it.
  private var attemptedSubscriptionSessionJWSHashes = Set<Data>()

  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    sessionStore: BackendSessionStore? = nil,
    proofProvider: DeviceSessionProofProviding,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.sessionStore = sessionStore
    self.proofProvider = proofProvider
    self.diagnostics = diagnostics
    subscriptionSessionTimeout = ConnectionTimeouts.hosted
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
    createSessionChallenge = { request in
      try await apiClient.createSessionChallenge(request)
    }
    warmupHostedService = {
      try await apiClient.warmup()
    }
    session = sessionStore?.loadValidSession()
  }

  #if DEBUG
  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    sessionStore: BackendSessionStore? = nil,
    currentEntitlementJWS: @escaping @MainActor () async throws -> String,
    syncedCurrentEntitlementJWS: (@MainActor () async throws -> String)? = nil,
    createSubscriptionSession: @escaping @MainActor (SubscriptionSessionRequest) async throws -> BackendSessionResponse,
    createSelfHostedSession: @escaping @MainActor (SelfHostedSessionRequest) async throws -> BackendSessionResponse,
    diagnostics: DiagnosticsLogStore? = nil,
    subscriptionSessionTimeout: TimeInterval = ConnectionTimeouts.hosted,
    warmupHostedService: @escaping @MainActor () async throws -> Void = {},
    proofProvider: DeviceSessionProofProviding,
    createSessionChallenge: (@MainActor (SessionChallengeRequest) async throws -> SessionChallengeResponse)? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.sessionStore = sessionStore
    self.proofProvider = proofProvider
    self.diagnostics = diagnostics
    self.subscriptionSessionTimeout = subscriptionSessionTimeout
    self.currentEntitlementJWS = currentEntitlementJWS
    self.syncedCurrentEntitlementJWS = syncedCurrentEntitlementJWS ?? currentEntitlementJWS
    self.createSubscriptionSession = createSubscriptionSession
    self.createSelfHostedSession = createSelfHostedSession
    self.warmupHostedService = warmupHostedService
    self.createSessionChallenge = createSessionChallenge ?? { _ in
      SessionChallengeResponse(
        protocolVersion: 3,
        proofKind: configurationStore.mode == .hosted ? "appAttest" : "secureEnclaveP256",
        challengeToken: "test-session-challenge",
        expiresAt: .distantFuture
      )
    }
    session = sessionStore?.loadValidSession()
  }
  #endif

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

  func accessTokenRecoveringIfNeeded(allowInteractiveRecovery: Bool = true) async -> String? {
    await recoverSessionIfNeeded(allowInteractiveRecovery: allowInteractiveRecovery)
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
    await runQueuedExplicitSubscriptionOperation {
      await self.restoreCurrentSubscription()
    }
  }

  private func restoreCurrentSubscription() async {
    let configurationRevision = configurationStore.revision
    do {
      try prepareHostedRequest(configurationRevision: configurationRevision)
    } catch {
      recordSubscriptionRestoreConfigurationChange()
      return
    }
    isConnecting = true
    errorMessage = nil
    statusMessage = "Checking Subscription…"
    diagnostics?.record(source: .auth, title: "Subscription restore started")

    do {
      let signedTransactionInfo = try await syncedCurrentEntitlementJWS()
      try prepareHostedRequest(configurationRevision: configurationRevision)
      _ = await establishSubscriptionSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Connecting to PumpSync…",
        title: "PumpSync subscription restored",
        publishesErrors: true,
        expectedConfigurationRevision: configurationRevision
      )
    } catch StoreKitSubscriptionError.noActiveSubscription {
      guard isCurrentHostedConfiguration(configurationRevision) else {
        recordSubscriptionRestoreConfigurationChange()
        return
      }
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
      guard !(error is SubscriptionConfigurationChangedError),
            isCurrentHostedConfiguration(configurationRevision) else {
        recordSubscriptionRestoreConfigurationChange()
        return
      }
      preserveValidSessionOrClear()
      let message = subscriptionConnectionMessage(for: safeMessage("PumpSync subscription access could not be verified.", error: error))
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Subscription restore failed")
      isConnecting = false
    }
  }

  func activateSubscription(signedTransactionInfo: String) async {
    await runQueuedExplicitSubscriptionOperation {
      _ = await self.establishSubscriptionSession(
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
      await handleActiveSubscriptionTransactionUpdate(
        signedTransactionInfo: result.jwsRepresentation,
        diagnosticSummary: transaction.diagnosticSummary(active: true),
        finish: { await transaction.finish() }
      )
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

  /// Handles only verified, active updates from `Transaction.updates` after
  /// product and connection-mode validation.
  func handleActiveSubscriptionTransactionUpdate(
    signedTransactionInfo: String,
    diagnosticSummary: String,
    finish: @MainActor () async -> Void
  ) async {
    let configurationRevision = configurationStore.revision
    await finish()

    let transactionHash = Self.subscriptionJWSHash(signedTransactionInfo)
    guard !attemptedSubscriptionSessionJWSHashes.contains(transactionHash) else {
      diagnostics?.record(
        source: .auth,
        title: "PumpSync subscription transaction update skipped",
        message: "reason=duplicateSessionAttempt \(diagnosticSummary)"
      )
      return
    }

    while !attemptedSubscriptionSessionJWSHashes.contains(transactionHash) {
      guard isCurrentHostedConfiguration(configurationRevision) else {
        diagnostics?.record(
          source: .auth,
          title: "PumpSync subscription transaction update skipped",
          message: "reason=connectionModeChanged \(diagnosticSummary)"
        )
        return
      }

      var configurationChanged = false
      await runCoalescedSubscriptionOperation {
        // The mode can change while this update is waiting for another
        // subscription operation. Check again in the operation that actually
        // acquires the slot so a hosted JWS is never sent to a self-hosted URL.
        guard self.isCurrentHostedConfiguration(configurationRevision) else {
          configurationChanged = true
          return
        }

        configurationChanged = await self.establishSubscriptionSession(
          signedTransactionInfo: signedTransactionInfo,
          activityMessage: "Connecting to PumpSync…",
          title: "PumpSync subscription purchased",
          publishesErrors: true,
          expectedConfigurationRevision: configurationRevision
        )
      }

      if configurationChanged {
        diagnostics?.record(
          source: .auth,
          title: "PumpSync subscription transaction update skipped",
          message: "reason=connectionModeChanged \(diagnosticSummary)"
        )
        return
      }
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
    let configurationRevision = configurationStore.revision
    guard isCurrentConfiguration(configurationRevision, mode: .selfHosted),
          configurationStore.apply(to: apiClient) else {
      errorMessage = "Enter a valid self-hosted service URL starting with https:// (http:// is only allowed for localhost)."
      statusMessage = errorMessage ?? statusMessage
      return
    }

    let operationID = UUID()
    selfHostedOperationID = operationID
    isConnecting = true
    errorMessage = nil
    statusMessage = "Connecting to self-hosted service..."
    diagnostics?.record(source: .auth, title: "Self-hosted session started")

    do {
      let request = try await makeSelfHostedSessionRequest(
        configurationRevision: configurationRevision,
        operationID: operationID
      )
      try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
      let createdSession = try await createSelfHostedSession(request)
      try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
      session = createdSession
      try? sessionStore?.save(createdSession)
      recordDemoModeIfNeeded(createdSession)
      statusMessage = Self.connectedStatusMessage(for: createdSession)
      diagnostics?.record(source: .auth, title: "Self-hosted session created")
    } catch {
      if error is BackendConfigurationChangedError
        || !isCurrentConfiguration(configurationRevision, mode: .selfHosted) {
        recordSelfHostedConfigurationChange()
        finishSelfHostedOperation(operationID)
        return
      }
      if error is SelfHostedOperationSupersededError || selfHostedOperationID != operationID {
        diagnostics?.record(
          source: .auth,
          title: "Self-hosted session stopped",
          message: "reason=connectionOperationSuperseded"
        )
        return
      }
      session = nil
      try? sessionStore?.delete()
      let message = safeMessage("Self-hosted connection could not be established.", error: error)
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Self-hosted session failed")
    }

    finishSelfHostedOperation(operationID)
  }

  func recoverSessionIfNeeded(allowInteractiveRecovery: Bool = true) async {
    if let session, sessionStore?.isValid(session) ?? !session.accessToken.isEmpty {
      diagnostics?.record(source: .auth, title: "Connection session cache hit", message: "cacheHit=true totalMs=0")
      return
    }

    let recoverableSession = session.flatMap { current in
      if sessionStore?.isRenewable(current) == true {
        return current
      }
      return nil
    } ?? sessionStore?.loadRecoverableSession()
    if let recoverableSession {
      session = recoverableSession
      if sessionStore?.isValid(recoverableSession) == true {
        errorMessage = nil
        statusMessage = Self.connectedStatusMessage(for: recoverableSession)
        diagnostics?.record(source: .auth, title: "Connection session restored")
        return
      }

      if await runCoalescedRenewableRefresh(recoverableSession) {
        return
      }

      // A transport/server failure leaves the renewable session and App Attest
      // registration intact. Do not convert an ambiguous refresh result into a
      // new enrollment/key; retry recovery later.
      if session != nil {
        return
      }

      if !allowInteractiveRecovery {
        return
      }
    }

    if !allowInteractiveRecovery {
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Background session recovery stopped",
        message: "interactiveRecovery=false renewableCredential=false"
      )
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
    subscriptionOperationID = nil
    subscriptionOperationTask = nil
    renewableRefreshOperationID = nil
    renewableRefreshOperationKey = nil
    renewableRefreshTask = nil
    selfHostedOperationID = nil
    session = nil
    try? sessionStore?.delete()
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
    isConnecting = false
    diagnostics?.record(source: .auth, title: "Connection session reset")
  }

  func clearSessionForAuthenticationFailure() {
    session = nil
    try? sessionStore?.delete()
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
    diagnostics?.record(source: .auth, severity: .warning, title: "Connection session expired")
  }

  @discardableResult
  private func establishSubscriptionSession(
    signedTransactionInfo: String,
    activityMessage: String,
    title: String,
    publishesErrors: Bool,
    expectedConfigurationRevision: Int? = nil,
    allowsRejectedAssertionRetry: Bool = true
  ) async -> Bool {
    let configurationRevision = expectedConfigurationRevision ?? configurationStore.revision
    attemptedSubscriptionSessionJWSHashes.insert(Self.subscriptionJWSHash(signedTransactionInfo))
    do {
      try prepareHostedRequest(configurationRevision: configurationRevision)
    } catch {
      recordSubscriptionConfigurationChange()
      return true
    }

    let previousSession = session
    let hasValidPreviousSession = previousSession.map { sessionStore?.isValid($0) ?? !$0.accessToken.isEmpty } ?? false
    isConnecting = true
    errorMessage = nil
    statusMessage = activityMessage
    diagnostics?.record(source: .auth, title: "Subscription session started")

    let backendStartedAt = Date()
    var timeoutKind = SubscriptionSessionTimeoutKind.none
    var enrollmentKeyId: String?
    var enrollmentRequestId: String?
    var enrollmentProofKind: String?
    var enrollmentPreparation: HostedDeviceProofPreparation?
    var enrollmentSubmissionStarted = false
    var enrollmentRegistered = false
    var rejectedAssertionRetry: RejectedAssertionRetry?
    do {
      let warmupStartedAt = Date()
      do {
        try await warmupHostedService()
      } catch {
        let timeoutKind = SubscriptionSessionTimeoutKind(error: error)
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Hosted service warm-up failed",
          message: "timeoutKind=\(timeoutKind.rawValue) \(DiagnosticsLogStore.redacted(error.localizedDescription))"
        )
        throw HostedServiceWarmupError(timeoutKind: timeoutKind)
      }
      try prepareHostedRequest(configurationRevision: configurationRevision)
      diagnostics?.record(
        source: .auth,
        title: "Hosted service warm-up completed",
        message: "elapsedMs=\(elapsedMilliseconds(since: warmupStartedAt))"
      )

      let request = try await makeSubscriptionSessionRequest(
        signedTransactionInfo: signedTransactionInfo,
        configurationRevision: configurationRevision
      )
      defer {
        _ = proofProvider.releaseHostedProofOperation(requestId: request.deviceEnrollment.requestId)
      }
      enrollmentKeyId = request.deviceEnrollment.keyId
      enrollmentRequestId = request.deviceEnrollment.requestId
      enrollmentProofKind = request.deviceEnrollment.proofKind
      enrollmentPreparation = request.deviceEnrollment.preparation
      try prepareHostedRequest(configurationRevision: configurationRevision)
      guard try proofProvider.markHostedEnrollmentSubmissionStarted(
        keyId: request.deviceEnrollment.keyId,
        requestId: request.deviceEnrollment.requestId
      ) else {
        throw SubscriptionEnrollmentStateChangedError()
      }
      enrollmentSubmissionStarted = true
      let sessionRequestStartedAt = Date()
      let createdSession: BackendSessionResponse
      do {
        createdSession = try await createSubscriptionSessionWithTimeout(
          request,
          configurationRevision: configurationRevision
        )
        diagnostics?.record(
          source: .auth,
          title: "Subscription session request completed",
          message: "elapsedMs=\(elapsedMilliseconds(since: sessionRequestStartedAt)) proofKind=\(request.deviceEnrollment.proofKind) outcome=success"
        )
      } catch {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Subscription session request failed",
          message: "elapsedMs=\(elapsedMilliseconds(since: sessionRequestStartedAt)) proofKind=\(request.deviceEnrollment.proofKind) outcome=failure backendCode=\((error as? APIClientError)?.backendCode ?? "none")"
        )
        throw error
      }
      guard try proofProvider.markHostedEnrollmentRegistered(
        keyId: request.deviceEnrollment.keyId,
        requestId: request.deviceEnrollment.requestId
      ) else {
        throw SubscriptionEnrollmentStateChangedError()
      }
      enrollmentRegistered = true
      try prepareHostedRequest(configurationRevision: configurationRevision)
      session = createdSession
      try? sessionStore?.save(createdSession)
      statusMessage = "PumpSync subscription active"
      diagnostics?.record(source: .auth, title: title)
    } catch {
      timeoutKind = SubscriptionSessionTimeoutKind(error: error)
      let apiError = error as? APIClientError
      if let proofError = error as? DeviceSessionProofError,
         case .hostedProofOperationInProgress = proofError {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Hosted security operation deferred",
          message: "reason=proofOperationInProgress"
        )
      }
      if let enrollmentKeyId,
         let enrollmentRequestId,
         !enrollmentRegistered,
         error is SubscriptionConfigurationChangedError,
         (try? proofProvider.discardUnsubmittedHostedEnrollment(
           keyId: enrollmentKeyId,
           requestId: enrollmentRequestId
         )) == true {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Unsubmitted App Attest enrollment discarded",
          message: "reason=connectionModeChanged backendSubmitted=false"
        )
      } else if let enrollmentKeyId,
         let enrollmentRequestId,
         apiError?.isDeviceKeyReenrollmentRequired == true,
         (try? proofProvider.discardDefinitivelyFailedHostedEnrollment(
           keyId: enrollmentKeyId,
           requestId: enrollmentRequestId
         )) == true {
        if allowsRejectedAssertionRetry, enrollmentProofKind == "assertion" {
          rejectedAssertionRetry = .freshAttestation
        }
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "App Attest key re-enrollment required",
          message: "protocolVersion=3 proofKind=\(enrollmentProofKind ?? "unknown") preparation=\(enrollmentPreparation?.rawValue ?? "unknown") backendCode=device_key_reenrollment_required localAction=discardKey"
        )
      } else if let enrollmentKeyId,
         let enrollmentRequestId,
         apiError?.isDeviceEnrollmentRequired == true,
         (try? proofProvider.discardDefinitivelyFailedHostedEnrollment(
           keyId: enrollmentKeyId,
           requestId: enrollmentRequestId
         )) == true {
        if allowsRejectedAssertionRetry, enrollmentProofKind == "assertion" {
          rejectedAssertionRetry = .freshAttestation
        }
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "App Attest enrollment required",
          message: "protocolVersion=3 proofKind=\(enrollmentProofKind ?? "unknown") preparation=\(enrollmentPreparation?.rawValue ?? "unknown") backendCode=device_enrollment_required localAction=discardKey"
        )
      } else if let enrollmentKeyId,
         let enrollmentRequestId,
         apiError?.isDeviceProofRejected == true,
         (try? proofProvider.resolveRejectedHostedEnrollment(
           keyId: enrollmentKeyId,
           requestId: enrollmentRequestId
         )) == true {
        if allowsRejectedAssertionRetry, enrollmentProofKind == "assertion" {
          rejectedAssertionRetry = .freshAssertion
        }
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Rejected App Attest proof handled",
          message: "protocolVersion=3 proofKind=\(enrollmentProofKind ?? "unknown") preparation=\(enrollmentPreparation?.rawValue ?? "unknown") backendCode=device_proof_rejected localAction=\(enrollmentProofKind == "assertion" ? "retainKey" : "discardKey")"
        )
      } else if enrollmentSubmissionStarted,
                !enrollmentRegistered,
                timeoutKind != .none
                  || apiError?.hasAmbiguousOutcome == true
                  || (error as NSError).domain == NSURLErrorDomain {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "App Attest enrollment requires reconciliation",
          message: "protocolVersion=3 recovery=freshAssertion"
        )
      } else if let enrollmentKeyId,
                let enrollmentRequestId,
                !enrollmentRegistered,
                enrollmentSubmissionStarted,
                enrollmentProofKind == "attestation",
                let apiError,
                !apiError.hasAmbiguousOutcome,
                (try? proofProvider.discardDefinitivelyFailedHostedEnrollment(
                  keyId: enrollmentKeyId,
                  requestId: enrollmentRequestId
                )) == true {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Definitively failed App Attest enrollment discarded",
          message: "protocolVersion=3 proofKind=attestation backendOutcome=definitive"
        )
      }
      if error is SubscriptionConfigurationChangedError
        || !isCurrentHostedConfiguration(configurationRevision) {
        recordSubscriptionConfigurationChange()
        return true
      }

      if let rejectedAssertionRetry {
        let backendMs = Int(Date().timeIntervalSince(backendStartedAt) * 1_000)
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "App Attest assertion rejected; retrying secure connection",
          message: "backendMs=\(backendMs) protocolVersion=3 retry=\(rejectedAssertionRetry.rawValue)"
        )
        return await establishSubscriptionSession(
          signedTransactionInfo: signedTransactionInfo,
          activityMessage: activityMessage,
          title: title,
          publishesErrors: publishesErrors,
          expectedConfigurationRevision: configurationRevision,
          allowsRejectedAssertionRetry: false
        )
      }

      if hasValidPreviousSession {
        session = previousSession
      } else {
        session = nil
        try? sessionStore?.delete()
      }
      if publishesErrors || error is HostedServiceWarmupError {
        let message = error is HostedServiceWarmupError
          ? HostedServiceWarmupError.userMessage
          : subscriptionConnectionMessage(for: safeMessage("PumpSync subscription access could not be verified.", error: error))
        errorMessage = message
        statusMessage = message
      } else {
        if hasValidPreviousSession, let previousSession {
          statusMessage = Self.connectedStatusMessage(for: previousSession)
        } else {
          resetDisconnectedStatus()
        }
      }
      recordSubscriptionSessionFailure(error)
    }

    let backendMs = Int(Date().timeIntervalSince(backendStartedAt) * 1_000)
    diagnostics?.record(
      source: .auth,
      severity: timeoutKind == .none ? .info : .warning,
      title: "Subscription session timing",
      message: "backendMs=\(backendMs) timedOut=\(timeoutKind != .none) timeoutKind=\(timeoutKind.rawValue) cacheHit=false"
    )

    isConnecting = false
    return false
  }

  private func recoverSubscriptionSession() async {
    let configurationRevision = configurationStore.revision
    do {
      try prepareHostedRequest(configurationRevision: configurationRevision)
    } catch {
      recordSubscriptionRecoveryConfigurationChange()
      return
    }
    let startedAt = Date()
    diagnostics?.record(source: .auth, title: "Subscription recovery started")

    do {
      let entitlementStartedAt = Date()
      let signedTransactionInfo = try await currentEntitlementJWS()
      try prepareHostedRequest(configurationRevision: configurationRevision)
      let entitlementMs = Int(Date().timeIntervalSince(entitlementStartedAt) * 1_000)
      let configurationChanged = await establishSubscriptionSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Connecting to PumpSync…",
        title: "PumpSync subscription recovered",
        publishesErrors: false,
        expectedConfigurationRevision: configurationRevision
      )
      if configurationChanged {
        return
      }
      diagnostics?.record(source: .auth, title: "Subscription recovery timing", message: "entitlementMs=\(entitlementMs) totalMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) cacheHit=false")
    } catch StoreKitSubscriptionError.noActiveSubscription {
      guard isCurrentHostedConfiguration(configurationRevision) else {
        recordSubscriptionRecoveryConfigurationChange()
        return
      }
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
      guard !(error is SubscriptionConfigurationChangedError),
            isCurrentHostedConfiguration(configurationRevision) else {
        recordSubscriptionRecoveryConfigurationChange()
        return
      }
      session = nil
      try? sessionStore?.delete()
      resetDisconnectedStatus()
      diagnostics?.record(error: error, source: .auth, title: "Subscription recovery failed")
    }
  }

  private func recoverSelfHostedSession() async {
    let configurationRevision = configurationStore.revision
    guard isCurrentConfiguration(configurationRevision, mode: .selfHosted),
          configurationStore.apply(to: apiClient) else {
      diagnostics?.record(source: .auth, severity: .warning, title: "Self-hosted recovery skipped", message: "No valid self-hosted service URL is configured.")
      return
    }

    let operationID = UUID()
    selfHostedOperationID = operationID
    isConnecting = true
    errorMessage = nil
    statusMessage = "Connecting to self-hosted service..."
    diagnostics?.record(source: .auth, title: "Self-hosted recovery started")

    do {
      let request = try await makeSelfHostedSessionRequest(
        configurationRevision: configurationRevision,
        operationID: operationID
      )
      try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
      let createdSession = try await createSelfHostedSession(request)
      try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
      session = createdSession
      try? sessionStore?.save(createdSession)
      recordDemoModeIfNeeded(createdSession)
      statusMessage = Self.connectedStatusMessage(for: createdSession)
      diagnostics?.record(source: .auth, title: "Self-hosted session recovered")
    } catch {
      if error is BackendConfigurationChangedError
        || !isCurrentConfiguration(configurationRevision, mode: .selfHosted) {
        recordSelfHostedConfigurationChange()
        finishSelfHostedOperation(operationID)
        return
      }
      if error is SelfHostedOperationSupersededError || selfHostedOperationID != operationID {
        diagnostics?.record(
          source: .auth,
          title: "Self-hosted session stopped",
          message: "reason=connectionOperationSuperseded"
        )
        return
      }
      session = nil
      try? sessionStore?.delete()
      resetDisconnectedStatus()
      diagnostics?.record(error: error, source: .auth, title: "Self-hosted recovery failed")
    }

    finishSelfHostedOperation(operationID)
  }

  private func makeSubscriptionSessionRequest(
    signedTransactionInfo: String,
    configurationRevision: Int
  ) async throws -> SubscriptionSessionRequest {
    let requestHash = DeviceSessionProofProvider.base64URL(
      Self.subscriptionJWSHash(signedTransactionInfo)
    )
    try prepareHostedRequest(configurationRevision: configurationRevision)
    let challengeStartedAt = Date()
    let challenge = try await createSessionChallenge(SessionChallengeRequest(
      installationId: configurationStore.installationId,
      purpose: "hostedEnrollment",
      requestHash: requestHash
    ))
    try prepareHostedRequest(configurationRevision: configurationRevision)
    guard challenge.protocolVersion == 3, challenge.proofKind == "appAttest", challenge.expiresAt > Date() else {
      throw DeviceSessionProofError.appAttestUnavailable
    }
    diagnostics?.record(
      source: .auth,
      title: "Hosted session challenge received",
      message: "elapsedMs=\(elapsedMilliseconds(since: challengeStartedAt)) proofKind=\(challenge.proofKind)"
    )
    let proofStartedAt = Date()
    let enrollment = try await proofProvider.hostedEnrollment(
      challenge: challenge,
      installationId: configurationStore.installationId,
      signedTransactionInfo: signedTransactionInfo
    )
    diagnostics?.record(
      source: .auth,
      title: "Hosted device proof prepared",
      message: "elapsedMs=\(elapsedMilliseconds(since: proofStartedAt)) proofKind=\(enrollment.proofKind) preparation=\(enrollment.preparation.rawValue) clientDataFingerprint=\(enrollment.clientDataFingerprint)"
    )
    return SubscriptionSessionRequest(
      signedTransactionInfo: signedTransactionInfo,
      installationId: configurationStore.installationId,
      deviceEnrollment: enrollment
    )
  }

  private func makeSelfHostedSessionRequest(
    configurationRevision: Int,
    operationID: UUID
  ) async throws -> SelfHostedSessionRequest {
    try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
    let challenge = try await createSessionChallenge(SessionChallengeRequest(
      installationId: configurationStore.installationId,
      purpose: "selfHostedEnrollment",
      requestHash: nil
    ))
    try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
    guard challenge.protocolVersion == 3, challenge.proofKind == "secureEnclaveP256", challenge.expiresAt > Date() else {
      throw DeviceSessionProofError.secureEnclaveUnavailable
    }
    let enrollment = try proofProvider.selfHostedEnrollment(
      challenge: challenge,
      installationId: configurationStore.installationId
    )
    try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
    return SelfHostedSessionRequest(
      installationId: configurationStore.installationId,
      deviceEnrollment: enrollment
    )
  }

  private func refreshRenewableSession(_ currentSession: BackendSessionResponse) async -> Bool {
    let configurationRevision = configurationStore.revision
    let mode = configurationStore.mode
    do {
      try prepareConfiguredRequest(configurationRevision: configurationRevision, mode: mode)
    } catch {
      recordRefreshConfigurationChange()
      return false
    }
    let startedAt = Date()
    diagnostics?.record(
      source: .auth,
      title: "Renewable session refresh started",
      message: "protocolVersion=3 serviceMode=\(currentSession.serviceMode)"
    )
    do {
      let request = try await proofProvider.refreshRequest(
        session: currentSession,
        installationId: configurationStore.installationId,
        mode: mode
      )
      defer {
        if mode == .hosted {
          _ = proofProvider.releaseHostedProofOperation(requestId: request.requestId)
        }
      }
      try prepareConfiguredRequest(configurationRevision: configurationRevision, mode: mode)
      let refreshed = try await apiClient.refreshSession(request, mode: mode)
      try prepareConfiguredRequest(configurationRevision: configurationRevision, mode: mode)
      guard refreshed.protocolVersion == 3, refreshed.serviceMode == currentSession.serviceMode else {
        throw APIClientError.invalidResponse
      }
      guard isCurrentRefreshSource(currentSession) else {
        diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh stopped",
          message: "reason=sessionSuperseded"
        )
        return isSignedIn
      }

      session = refreshed
      try sessionStore?.save(refreshed)
      errorMessage = nil
      statusMessage = Self.connectedStatusMessage(for: refreshed)
      diagnostics?.record(
        source: .auth,
        title: "Renewable session refresh completed",
        message: "protocolVersion=3 elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
      )
      return true
    } catch {
      if let proofError = error as? DeviceSessionProofError,
         case .hostedProofOperationInProgress = proofError {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Hosted security operation deferred",
          message: "reason=proofOperationInProgress"
        )
      }
      if error is BackendConfigurationChangedError
        || !isCurrentConfiguration(configurationRevision, mode: mode) {
        recordRefreshConfigurationChange()
        return false
      }
      guard isCurrentRefreshSource(currentSession) else {
        diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh stopped",
          message: "reason=sessionSuperseded"
        )
        return isSignedIn
      }
      let invalidAppAttestKey: Bool
      if case .invalidKey? = error as? AppAttestClientError {
        invalidAppAttestKey = true
      } else {
        invalidAppAttestKey = false
      }
      let permanentlyRejected = (error as? APIClientError)?.isAuthenticationFailure == true || invalidAppAttestKey
      if permanentlyRejected {
        session = nil
        try? sessionStore?.delete()
      } else {
        session = currentSession
      }
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Renewable session refresh failed",
        message: "permanentlyRejected=\(permanentlyRejected) elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(safeMessage("refresh failed", error: error))"
      )
      return false
    }
  }

  private func runCoalescedRenewableRefresh(_ source: BackendSessionResponse) async -> Bool {
    let key = RenewableRefreshOperationKey(
      configurationRevision: configurationStore.revision,
      mode: configurationStore.mode,
      sessionFamilyId: source.sessionFamilyId
    )
    if let renewableRefreshTask,
       renewableRefreshOperationKey == key {
      diagnostics?.record(
        source: .auth,
        title: "Renewable session refresh coalesced",
        message: "coalesced=true"
      )
      return await renewableRefreshTask.value
    }

    let operationID = UUID()
    let task = Task { @MainActor [weak self] in
      guard let self else {
        return false
      }
      let result = await self.refreshRenewableSession(source)
      if self.renewableRefreshOperationID == operationID {
        self.renewableRefreshTask = nil
        self.renewableRefreshOperationID = nil
        self.renewableRefreshOperationKey = nil
      }
      return result
    }
    renewableRefreshOperationID = operationID
    renewableRefreshOperationKey = key
    renewableRefreshTask = task
    return await task.value
  }

  private func isCurrentRefreshSource(_ source: BackendSessionResponse) -> Bool {
    guard let current = session else {
      return false
    }
    return current.protocolVersion == source.protocolVersion
      && current.serviceMode == source.serviceMode
      && current.sessionFamilyId == source.sessionFamilyId
      && current.refreshToken == source.refreshToken
  }

  private func resetDisconnectedStatus() {
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
  }

  private func runQueuedExplicitSubscriptionOperation(
    _ operation: @escaping @MainActor () async -> Void
  ) async {
    let configurationRevision = configurationStore.revision
    while !Task.isCancelled,
          configurationStore.revision == configurationRevision {
      let executed = await runCoalescedSubscriptionOperation {
        guard self.configurationStore.revision == configurationRevision else {
          return
        }
        await operation()
      }
      if executed {
        return
      }
    }
  }

  @discardableResult
  private func runCoalescedSubscriptionOperation(
    _ operation: @escaping @MainActor () async -> Void
  ) async -> Bool {
    if let subscriptionOperationTask {
      diagnostics?.record(source: .auth, title: "Subscription operation coalesced", message: "coalesced=true")
      await subscriptionOperationTask.value
      return false
    }

    let operationID = UUID()
    let task = Task { @MainActor [weak self] in
      await operation()
      guard self?.subscriptionOperationID == operationID else {
        return
      }
      self?.subscriptionOperationTask = nil
      self?.subscriptionOperationID = nil
    }
    subscriptionOperationID = operationID
    subscriptionOperationTask = task
    await task.value
    return true
  }

  private func createSubscriptionSessionWithTimeout(
    _ request: SubscriptionSessionRequest,
    configurationRevision: Int
  ) async throws -> BackendSessionResponse {
    try await withCheckedThrowingContinuation { continuation in
      var hasResumed = false
      var timeoutTask: Task<Void, Never>?

      let backendTask = Task { @MainActor in
        do {
          try prepareHostedRequest(configurationRevision: configurationRevision)
          let response = try await createSubscriptionSession(request)
          guard !hasResumed else { return }
          hasResumed = true
          timeoutTask?.cancel()
          continuation.resume(returning: response)
        } catch {
          guard !hasResumed else { return }
          hasResumed = true
          timeoutTask?.cancel()
          continuation.resume(throwing: error)
        }
      }

      timeoutTask = Task { @MainActor in
        do {
          try await Task.sleep(for: .seconds(subscriptionSessionTimeout))
        } catch {
          return
        }
        guard !hasResumed else { return }
        hasResumed = true
        backendTask.cancel()
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

  private func elapsedMilliseconds(since startedAt: Date) -> Int {
    Int(Date().timeIntervalSince(startedAt) * 1_000)
  }

  private static func subscriptionJWSHash(_ signedTransactionInfo: String) -> Data {
    Data(SHA256.hash(data: Data(signedTransactionInfo.utf8)))
  }

  private func isCurrentHostedConfiguration(_ revision: Int) -> Bool {
    isCurrentConfiguration(revision, mode: .hosted)
  }

  private func isCurrentConfiguration(_ revision: Int, mode: BackendAccessMode) -> Bool {
    configurationStore.mode == mode && configurationStore.revision == revision
  }

  private func prepareHostedRequest(configurationRevision: Int) throws {
    guard isCurrentHostedConfiguration(configurationRevision),
          configurationStore.apply(to: apiClient) else {
      throw SubscriptionConfigurationChangedError()
    }
  }

  private func prepareSelfHostedRequest(configurationRevision: Int, operationID: UUID) throws {
    guard isCurrentConfiguration(configurationRevision, mode: .selfHosted),
          configurationStore.apply(to: apiClient) else {
      throw BackendConfigurationChangedError()
    }
    guard selfHostedOperationID == operationID else {
      throw SelfHostedOperationSupersededError()
    }
  }

  private func prepareConfiguredRequest(configurationRevision: Int, mode: BackendAccessMode) throws {
    guard isCurrentConfiguration(configurationRevision, mode: mode),
          configurationStore.apply(to: apiClient) else {
      throw BackendConfigurationChangedError()
    }
  }

  private func finishSelfHostedOperation(_ operationID: UUID) {
    guard selfHostedOperationID == operationID else {
      return
    }
    selfHostedOperationID = nil
    isConnecting = false
  }

  private func recordSubscriptionConfigurationChange() {
    diagnostics?.record(
      source: .auth,
      title: "Subscription session stopped",
      message: "reason=connectionModeChanged"
    )
  }

  private func recordSubscriptionRestoreConfigurationChange() {
    diagnostics?.record(
      source: .auth,
      title: "Subscription restore stopped",
      message: "reason=connectionModeChanged"
    )
  }

  private func recordSubscriptionRecoveryConfigurationChange() {
    diagnostics?.record(
      source: .auth,
      title: "Subscription recovery stopped",
      message: "reason=connectionModeChanged"
    )
  }

  private func recordSelfHostedConfigurationChange() {
    diagnostics?.record(
      source: .auth,
      title: "Self-hosted session stopped",
      message: "reason=connectionModeChanged"
    )
  }

  private func recordRefreshConfigurationChange() {
    diagnostics?.record(
      source: .auth,
      title: "Renewable session refresh stopped",
      message: "reason=connectionModeChanged"
    )
  }

  private func recordSubscriptionSessionFailure(_ error: Error) {
    guard let apiError = error as? APIClientError,
          apiError.backendCode == "invalid_app_store_transaction" else {
      diagnostics?.record(error: error, source: .auth, title: "Subscription session failed")
      return
    }

    var message = "The App Store subscription credential was rejected by PumpSync. backendCode=invalid_app_store_transaction"
    if let correlationId = apiError.correlationId, !correlationId.isEmpty {
      message += " Reference: \(correlationId)."
    }
    diagnostics?.record(source: .auth, severity: .error, title: "Subscription session failed", message: message)
  }

  private func subscriptionConnectionMessage(for message: String) -> String {
    if message == HostedServiceWarmupError.userMessage {
      return message
    }

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

private struct SubscriptionConfigurationChangedError: Error {}

private struct SubscriptionEnrollmentStateChangedError: Error {}

private struct BackendConfigurationChangedError: Error {}

private struct SelfHostedOperationSupersededError: Error {}

private struct HostedServiceWarmupError: LocalizedError {
  static let userMessage = "The PumpSync service is temporarily unavailable. Try again."

  let timeoutKind: SubscriptionSessionTimeoutKind

  var errorDescription: String? { Self.userMessage }
}

private enum SubscriptionSessionTimeoutKind: String {
  case none
  case networkRequest
  case connectionOperation

  init(error: Error) {
    if let error = error as? HostedServiceWarmupError {
      self = error.timeoutKind
    } else if error is SubscriptionSessionTimeoutError {
      self = .connectionOperation
    } else {
      let error = error as NSError
      self = error.domain == NSURLErrorDomain && error.code == NSURLErrorTimedOut ? .networkRequest : .none
    }
  }
}

private enum RejectedAssertionRetry: String {
  case freshAssertion
  case freshAttestation
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
