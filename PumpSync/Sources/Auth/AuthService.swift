import CryptoKit
import Foundation
import Observation
import StoreKit

enum BackendAccessMode: String, Codable, CaseIterable, Identifiable {
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
      defaults?.set(mode.rawValue, forKey: Self.modeKey)
      if mode != oldValue {
        revision &+= 1
      }
    }
  }

  var selfHostedBaseURLString: String {
    didSet {
      defaults?.set(selfHostedBaseURLString, forKey: Self.selfHostedBaseURLKey)
      if selfHostedBaseURLString != oldValue {
        revision &+= 1
      }
    }
  }

  let installationId: String
  private(set) var revision = 0

  private let defaults: UserDefaults?
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

  private init(selfHostedBaseURL: URL, installationId: String) {
    defaults = nil
    mode = .selfHosted
    selfHostedBaseURLString = selfHostedBaseURL.absoluteString
    self.installationId = installationId
  }

  static func ephemeral(selfHostedBaseURL: URL, installationId: String) -> BackendConfigurationStore {
    BackendConfigurationStore(selfHostedBaseURL: selfHostedBaseURL, installationId: installationId)
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

enum SessionRecoveryPolicy: Equatable {
  case foreground
  case background
  case backgroundWithReenrollment

  var allowsInteractiveRecovery: Bool {
    self == .foreground
  }
}

enum AuthPurpose: String, Codable { case liveImport }

@MainActor
@Observable
final class AuthService {
  private enum MissingEntitlementDisposition {
    case clearUnusableSession
    case preserveRenewableSession

    var diagnosticName: String {
      switch self {
      case .clearUnusableSession:
        "clearUnusableSession"
      case .preserveRenewableSession:
        "preserveRenewableSession"
      }
    }
  }

  private let apiClient: PumpSyncAPIClient
  private let purpose: AuthPurpose
  private let configurationStore: BackendConfigurationStore
  private let sessionStore: BackendSessionStore?
  private let committer: AuthSessionCommitter
  private var authCommitBlocked = false
  private var recoveryFailure: SessionRecoveryReason? {
    get { SessionRecoveryContext.current?.failure }
    set { SessionRecoveryContext.current?.failure = newValue }
  }
  private var authOwnershipGeneration = UUID()
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
  private var connectionProgressVisible = false
  private var connectionProgressGeneration = UUID()
  private var connectionProgressLeases: [UUID: UUID] = [:]
  private var connectionIdentity: AuthConnectionIdentity?
  private(set) var session: BackendSessionResponse?
  private var incompleteInvalidation = false
  private var storedStatusMessage = "Connect to PumpSync or a self-hosted service"
  private var storedErrorMessage: String?
  private(set) var statusMessage: String {
    get { incompleteInvalidation ? AuthCommitError.invalidationIncomplete.localizedDescription : storedStatusMessage }
    set { storedStatusMessage = newValue }
  }
  private(set) var errorMessage: String? {
    get { incompleteInvalidation ? AuthCommitError.invalidationIncomplete.localizedDescription : storedErrorMessage }
    set { storedErrorMessage = newValue }
  }
  private var recoveryRequiresActiveSubscription = false
  private var transactionUpdatesTask: Task<Void, Never>?
  private var subscriptionOperationTask: Task<Void, Never>?
  private var subscriptionOperationID: UUID?
  private var subscriptionRecoveryAttempt: SessionRecoveryAttempt?
  private var subscriptionWaiters: [UUID: Set<UUID>] = [:]
  private struct RenewableRefreshOperationKey: Equatable {
    let configurationRevision: Int
    let mode: BackendAccessMode
    let sessionFamilyId: String
    let refreshToken: String
    let connectionId: UUID?
  }
  private var renewableRefreshTask: Task<Bool, Never>?
  private var renewableRefreshOperationID: UUID?
  private var renewableRefreshRecoveryAttempt: SessionRecoveryAttempt?
  private var renewableRefreshOperationKey: RenewableRefreshOperationKey?
  private var renewableRefreshWaiters: [UUID: Set<UUID>] = [:]
  private var selfHostedOperationID: UUID?
  private var sessionEstablished: (@MainActor () -> Void)?
  // Process-local by design: explicit purchase/restore actions may retry the
  // same JWS, while StoreKit's automatic update stream must not replay it.
  private var attemptedSubscriptionSessionJWSHashes = Set<Data>()

  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    sessionStore: BackendSessionStore? = nil,
    purpose: AuthPurpose = .liveImport,
    proofProvider: DeviceSessionProofProviding,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.apiClient = apiClient
    self.configurationStore = configurationStore
    self.sessionStore = sessionStore
    self.committer = AuthSessionCommitter(store: sessionStore)
    self.purpose = purpose
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
      SessionRecoveryContext.current?.backendCorrelationID = nil
      return try await apiClient.createSubscriptionSession(request, backendCorrelation: { SessionRecoveryContext.current?.backendCorrelationID = $0 })
    }
    createSelfHostedSession = { request in
      SessionRecoveryContext.current?.backendCorrelationID = nil
      return try await apiClient.createSelfHostedSession(request, backendCorrelation: { SessionRecoveryContext.current?.backendCorrelationID = $0 })
    }
    createSessionChallenge = { request in
      try await apiClient.createSessionChallenge(request)
    }
    warmupHostedService = {
      try await apiClient.warmup()
    }
    restoreStoredConnection()
  }

  #if DEBUG
  init(
    apiClient: PumpSyncAPIClient,
    configurationStore: BackendConfigurationStore,
    sessionStore: BackendSessionStore? = nil,
    purpose: AuthPurpose = .liveImport,
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
    self.committer = AuthSessionCommitter(store: sessionStore)
    self.purpose = purpose
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
    restoreStoredConnection()
  }
  #endif

  var importConfigurationSnapshot: ImportConfigurationSnapshot {
    ImportConfigurationSnapshot(backendIdentity: configurationStore.selectedBaseURL.map(ImportSessionSnapshot.canonicalBackendIdentity), revision: configurationStore.revision)
  }

  func currentImportSnapshot(credentialRevision: Int) -> ImportSessionSnapshot? {
    guard isSignedIn else { return nil }
    return operationImportSnapshot(credentialRevision: credentialRevision)
  }

  var connectionBinding: AuthConnectionBinding? {
    guard let selected = configurationStore.selectedBaseURL else { return nil }
    return AuthConnectionBinding(
      backendIdentity: ImportSessionSnapshot.canonicalBackendIdentity(selected),
      mode: configurationStore.mode,
      installationId: configurationStore.installationId,
      purpose: purpose
    )
  }

  var authenticatedConnection: AuthenticatedConnection? {
    guard !authCommitBlocked, let session, let identity = connectionIdentity,
          identity.binding == connectionBinding else { return nil }
    return AuthenticatedConnection(session: session, identity: identity)
  }

  private func storedConnection() throws -> AuthenticatedConnection? {
    guard let binding = connectionBinding else { throw AuthConnectionError.bindingMismatch }
    return try committer.load(binding: binding, proofProvider: proofProvider)
  }

  private func restoreStoredConnection() {
    do {
      guard let stored = try storedConnection(), (try? validateSessionPurpose(stored.session)) != nil else { return }
      if configurationStore.mode == .hosted, try proofProvider.hostedRecoveryDisposition() != .ready {
        authCommitBlocked = true
        connectionIdentity = stored.identity
        return
      }
      authCommitBlocked = false
      connectionIdentity = stored.identity
      if sessionIsValid(stored.session) { session = stored.session }
    } catch {
      authCommitBlocked = true
      session = nil
    }
  }

  private func publishCommitted(_ connection: AuthenticatedConnection) {
    if incompleteInvalidation {
      incompleteInvalidation = false
      storedErrorMessage = nil
      storedStatusMessage = Self.connectedStatusMessage(for: connection.session)
    }
    let changed = connectionIdentity != connection.identity || session != connection.session
    authCommitBlocked = false
    connectionIdentity = connection.identity
    session = connection.session
    // A confirmed late response remains committed, but a canceled auth owner
    // cannot grant a new sync execution through the reconciliation signal.
    if changed, !Task.isCancelled { sessionEstablished?() }
  }

  private func blockUnresolvedAuth() {
    if committer.hasUnresolvedSubmission {
      authCommitBlocked = true
      session = nil
    }
  }

  private func invalidateDurableAuth(replacesOwnership: Bool = false) -> Bool {
    if replacesOwnership {
      authOwnershipGeneration = UUID()
      proofProvider.invalidateHostedProofOperation()
    }
    authCommitBlocked = true
    session = nil
    connectionIdentity = nil
    do {
      try committer.invalidate()
      incompleteInvalidation = false
      authCommitBlocked = false
      return true
    } catch {
      incompleteInvalidation = true
      errorMessage = AuthCommitError.invalidationIncomplete.localizedDescription
      statusMessage = errorMessage ?? "Disconnection could not be saved."
      diagnostics?.record(source: .auth, severity: .error, title: "Connection invalidation incomplete")
      return false
    }
  }

  /// Enrollment replaces continuity even if the server reuses a family. Only
  /// refresh of the exact captured connection may retain its local identity.
  func installSession(_ response: BackendSessionResponse, installation: AuthSessionInstallation) throws {
    guard let binding = connectionBinding, response.serviceMode == binding.mode.rawValue else {
      throw AuthConnectionError.bindingMismatch
    }
    try validateSessionPurpose(response)
    let identity: AuthConnectionIdentity
    switch installation {
    case .enrollment:
      identity = AuthConnectionIdentity(id: UUID(), binding: binding)
    case .verifiedRefresh(let source):
      guard authenticatedConnection == source, source.identity.binding == binding else {
        throw AuthConnectionError.sourceReplaced
      }
      identity = source.identity
    }
    let connection = AuthenticatedConnection(session: response, identity: identity)
    try committer.install(connection)
    publishCommitted(connection)
  }

  /// Captures local continuity before recovery, including renewable credentials.
  func operationImportSnapshot(credentialRevision: Int) -> ImportSessionSnapshot? {
    guard let connection = authenticatedConnection ?? (try? storedConnection()),
          let selected = configurationStore.selectedBaseURL,
          connection.identity.binding == connectionBinding,
          ImportSessionSnapshot.canonicalBackendIdentity(selected) == ImportSessionSnapshot.canonicalBackendIdentity(apiClient.baseURL),
          !connection.session.sessionFamilyId.isEmpty,
          (try? validateSessionPurpose(connection.session)) != nil else { return nil }
    return ImportSessionSnapshot(
      backendIdentity: connection.identity.binding.backendIdentity,
      configurationRevision: configurationStore.revision,
      credentialRevision: credentialRevision,
      connectionId: connection.identity.id,
      dataSourceMode: DataSourceMode(rawValue: connection.session.dataSourceMode) ?? .unknown
    )
  }

  private func validateSessionPurpose(_ session: BackendSessionResponse) throws {
    let source = DataSourceMode(rawValue: session.dataSourceMode) ?? .unknown
    guard source != .unknown else { throw HealthImportError.unverifiedSource }
    if source == .syntheticDemo { throw HealthImportError.previewOnly }
  }

  private func sessionIsValid(_ session: BackendSessionResponse) -> Bool {
    sessionStore?.isValid(session) ?? BackendSessionStore.isValid(session, at: Date())
  }

  private func sessionIsRenewable(_ session: BackendSessionResponse) -> Bool {
    sessionStore?.isRenewable(session) ?? BackendSessionStore.isRenewable(session, at: Date())
  }

  var isSignedIn: Bool {
    guard let session, authenticatedConnection != nil, (try? validateSessionPurpose(session)) != nil else {
      return false
    }

    if let sessionStore {
      return sessionStore.isValid(session)
    }

    return BackendSessionStore.isValid(session, at: Date())
  }

  var accessToken: String? {
    guard isSignedIn else {
      return nil
    }

    return session?.accessToken
  }

  /// True only when hosted session recovery reached StoreKit and found no
  /// active entitlement. A missing session by itself is not a subscription
  /// failure: self-hosted and generic authentication failures remain Settings
  /// recovery paths.
  var requiresSubscriptionAction: Bool {
    configurationStore.mode == .hosted && recoveryRequiresActiveSubscription
  }

  var isHostedMode: Bool {
    configurationStore.mode == .hosted
  }

  func setConnectionProgressVisible(_ visible: Bool) {
    guard connectionProgressVisible != visible else {
      return
    }
    connectionProgressVisible = visible
    updateConnectionProgress()
  }

  private func beginConnectionProgressLease() -> UUID {
    let leaseID = UUID()
    connectionProgressLeases[leaseID] = connectionProgressGeneration
    updateConnectionProgress()
    return leaseID
  }

  private func endConnectionProgressLease(_ leaseID: UUID) {
    connectionProgressLeases.removeValue(forKey: leaseID)
    updateConnectionProgress()
  }

  private func invalidateConnectionProgressGeneration() {
    connectionProgressGeneration = UUID()
    connectionProgressLeases.removeAll()
    updateConnectionProgress()
  }

  private func updateConnectionProgress() {
    isConnecting = connectionProgressVisible
      && connectionProgressLeases.values.contains(connectionProgressGeneration)
  }

  func accessTokenRecoveringIfNeeded(policy: SessionRecoveryPolicy = .foreground) async -> String? {
    let outcome = await recoverSessionIfNeeded(policy: policy)
    guard !Task.isCancelled, case .ready(let connection, _) = outcome else { return nil }
    return connection.session.accessToken
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

  func connectUsingCurrentSubscription() async {
    await runQueuedExplicitSubscriptionOperation {
      await self.restoreCurrentSubscription()
    }
  }

  private func restoreCurrentSubscription() async {
    let ownershipGeneration = authOwnershipGeneration
    let configurationRevision = configurationStore.revision
    do {
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
    } catch {
      recordSubscriptionRestoreConfigurationChange()
      return
    }
    errorMessage = nil
    statusMessage = "Checking Subscription…"
    diagnostics?.record(source: .auth, title: "Subscription restore started")

    do {
      let signedTransactionInfo = try await syncedCurrentEntitlementJWS()
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
      _ = await establishSubscriptionSession(
        signedTransactionInfo: signedTransactionInfo,
        activityMessage: "Connecting to PumpSync…",
        title: "PumpSync subscription restored",
        publishesErrors: true,
        expectedConfigurationRevision: configurationRevision
      )
    } catch StoreKitSubscriptionError.noActiveSubscription {
      guard authOwnershipGeneration == ownershipGeneration, isCurrentHostedConfiguration(configurationRevision) else {
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
    } catch {
      guard authOwnershipGeneration == ownershipGeneration, !(error is SubscriptionConfigurationChangedError),
            isCurrentHostedConfiguration(configurationRevision) else {
        recordSubscriptionRestoreConfigurationChange()
        return
      }
      preserveValidSessionOrClear()
      let message = subscriptionConnectionMessage(for: safeMessage("PumpSync subscription access could not be verified.", error: error), error: error)
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Subscription restore failed")
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
      recordSubscriptionRevokedOrExpired(diagnosticSummary: transaction.diagnosticSummary(active: false))
    }

    if !transaction.isActiveSubscriptionEntitlement {
      await transaction.finish()
    }
  }

  func recordSubscriptionRevokedOrExpired(diagnosticSummary: String) {
    guard configurationStore.mode == .hosted, session != nil else { return }
    session = nil
    _ = invalidateDurableAuth(replacesOwnership: true)
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
    diagnostics?.record(source: .auth, severity: .warning, title: "PumpSync subscription revoked or expired", message: diagnosticSummary)
  }

  /// Handles only verified, active updates from `Transaction.updates` after
  /// product and connection-mode validation.
  func handleActiveSubscriptionTransactionUpdate(
    signedTransactionInfo: String,
    diagnosticSummary: String,
    finish: @MainActor () async -> Void
  ) async {
    let configurationRevision = configurationStore.revision
    let progressLeaseID = beginConnectionProgressLease()
    defer { endConnectionProgressLease(progressLeaseID) }
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
    diagnostics?.record(source: .auth, title: "PumpSync subscription purchase cancelled")
  }

  func recordSubscriptionPurchasePending() {
    preserveValidSessionOrClear()
    errorMessage = nil
    statusMessage = "Subscription purchase is pending App Store approval."
    diagnostics?.record(source: .auth, title: "PumpSync subscription purchase pending")
  }

  func recordSubscriptionPurchaseFailed(_ error: Error) {
    preserveValidSessionOrClear()
    let message = safeMessage("Subscription purchase could not be completed.", error: error)
    errorMessage = message
    statusMessage = message
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
    let progressLeaseID = beginConnectionProgressLease()
    defer { endConnectionProgressLease(progressLeaseID) }
    errorMessage = nil
    statusMessage = "Connecting to self-hosted service..."
    diagnostics?.record(source: .auth, title: "Self-hosted session started")

    do {
      let mutationLease = try await committer.acquireLease()
      defer { committer.releaseLease(mutationLease) }
      let request = try await makeSelfHostedSessionRequest(
        configurationRevision: configurationRevision,
        operationID: operationID
      )
      try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
      guard let binding = connectionBinding else { throw AuthConnectionError.bindingMismatch }
      let source = try committer.enrollmentSource(binding: binding, memory: authenticatedConnection)
      let journalID = try committer.begin(kind: .enrollment, binding: binding, source: source,
        proofRequestID: request.deviceEnrollment.requestId, proofKeyID: nil)
      try committer.submitted(journalID, binding: binding, source: source)
      let createdSession = try await createSelfHostedSession(request)
      guard isCurrentConfiguration(configurationRevision, mode: .selfHosted), selfHostedOperationID == operationID,
            connectionBinding == binding else { throw BackendConfigurationChangedError() }
      let committed = try committer.receive(createdSession, operationID: journalID, binding: binding, proofProvider: proofProvider)
      publishCommitted(committed)
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
      blockUnresolvedAuth()
      let message = safeMessage("Self-hosted connection could not be established.", error: error)
      errorMessage = message
      statusMessage = message
      diagnostics?.record(error: error, source: .auth, title: "Self-hosted session failed")
    }

    finishSelfHostedOperation(operationID)
  }

  @discardableResult
  func recoverSessionIfNeeded(policy: SessionRecoveryPolicy = .foreground, policyProvider: SessionRecoveryPolicyProvider? = nil, backendCorrelation: ((String?) -> Void)? = nil) async -> SessionRecoveryOutcome {
    let attempt = SessionRecoveryAttempt()
    let outcome = await SessionRecoveryContext.$policyProvider.withValue(policyProvider) {
      await SessionRecoveryContext.$current.withValue(attempt) {
        await recoverSession(policy: policy)
      }
    }
    backendCorrelation?(attempt.backendCorrelationID)
    return outcome
  }

  private func recoverSession(policy requestedPolicy: SessionRecoveryPolicy, forceHostedEnrollment: Bool = false) async -> SessionRecoveryOutcome {
    var policy: SessionRecoveryPolicy { SessionRecoveryContext.policyProvider?() ?? requestedPolicy }
    guard !Task.isCancelled else { return .canceled }
    let ownership = authOwnershipGeneration
    let configurationRevision = configurationStore.revision
    let binding = connectionBinding
    let previousIdentity = connectionIdentity
    let previousToken = session?.accessToken
    let wasValid = session.map { sessionIsValid($0) } == true && authenticatedConnection != nil
    recoveryFailure = nil
    if forceHostedEnrollment {
      await runCoalescedSubscriptionOperation {
        await self.recoverSubscriptionSession(policy: policy, missingEntitlementDisposition: .preserveRenewableSession)
      }
    } else {
      await performSessionRecovery(policy: policy)
    }
    guard !Task.isCancelled else { return .canceled }
    guard ownership == authOwnershipGeneration, configurationRevision == configurationStore.revision,
          binding == connectionBinding else { return .rejected(.connectionReplaced) }
    if incompleteInvalidation { return .deferred(.invalidationIncomplete) }
    do {
      if let pending = try committer.unresolvedRecoveryError() { return .deferred(Self.recoveryReason(for: pending)) }
    } catch { return .deferred(.storageUnavailable) }
    if let connection = authenticatedConnection, sessionIsValid(connection.session) {
      let transition: SessionRecoveryTransition = connection.identity != previousIdentity
        ? .reenrolled : (!wasValid || previousToken != connection.session.accessToken ? .refreshed : .cached)
      return .ready(connection, transition: transition)
    }
    let reason = recoveryFailure ?? (recoveryRequiresActiveSubscription ? .missingEntitlement : .interactiveRecoveryRequired)
    switch reason {
    case .missingEntitlement:
      return policy.allowsInteractiveRecovery ? .requiresUserAction(reason) : .deferred(reason)
    case .configurationInvalid, .interactiveRecoveryRequired:
      return .requiresUserAction(reason)
    case .authenticationRejected, .deviceProofRejected, .backendRejected, .unverifiedSource:
      return .rejected(reason)
    default:
      return .deferred(reason)
    }
  }

  private func performSessionRecovery(policy requestedPolicy: SessionRecoveryPolicy) async {
    var policy: SessionRecoveryPolicy { SessionRecoveryContext.policyProvider?() ?? requestedPolicy }
    if let task = subscriptionOperationTask {
      diagnostics?.record(source: .auth, title: "Subscription operation coalesced", message: "coalesced=true")
      let attempt = subscriptionRecoveryAttempt
      await awaitSubscriptionOperation(task, operationID: subscriptionOperationID)
      attempt?.replayRequestLinks()
      recoveryFailure = attempt?.failure
      if let correlation = attempt?.backendCorrelationID { SessionRecoveryContext.current?.backendCorrelationID = correlation }
      return
    }
    if !committer.isBusy {
      do {
        if configurationStore.mode == .hosted,
           case .reconciliationRequired(let keyID, let requestID) = try proofProvider.hostedRecoveryDisposition(),
           let binding = connectionBinding {
          try committer.adoptLegacyProofUncertainty(binding: binding, proofKeyID: keyID, proofRequestID: requestID)
        }
        if let repaired = try storedConnection() {
          authCommitBlocked = false
          connectionIdentity = repaired.identity
          session = repaired.session
        }
      } catch AuthCommitError.uncertainSubmission {
        recoveryFailure = .uncertainSubmission
        authCommitBlocked = true
        session = nil
        errorMessage = AuthCommitError.uncertainSubmission.localizedDescription
        guard policy == .foreground || policy == .backgroundWithReenrollment else { return }
        switch configurationStore.mode {
        case .hosted:
          await runCoalescedSubscriptionOperation { await self.recoverSubscriptionSession(policy: policy) }
        case .selfHosted:
          await recoverSelfHostedSession()
        }
        return
      } catch {
        recoveryFailure = Self.recoveryReason(for: error)
        authCommitBlocked = true
        session = nil
        errorMessage = "Your saved connection is unavailable. Try again after unlocking the device, or reconnect in Settings."
        return
      }
    }
    if configurationStore.mode == .hosted, !committer.isBusy {
      do {
        if try proofProvider.hostedRecoveryDisposition() != .ready,
           session != nil || connectionIdentity != nil {
          authCommitBlocked = true
          session = nil
          guard policy == .foreground || policy == .backgroundWithReenrollment else {
            recoveryFailure = .interactiveRecoveryRequired
            return
          }
          await runCoalescedSubscriptionOperation { await self.recoverSubscriptionSession(policy: policy) }
          return
        }
      } catch {
        recoveryFailure = Self.recoveryReason(for: error)
        authCommitBlocked = true
        session = nil
        return
      }
    }
    if let session, authenticatedConnection != nil, (try? validateSessionPurpose(session)) != nil, sessionIsValid(session) {
      diagnostics?.record(source: .auth, title: "Connection session cache hit", message: "cacheHit=true totalMs=0")
      return
    }

    let stored: AuthenticatedConnection?
    do {
      stored = authenticatedConnection == nil ? try storedConnection() : nil
    } catch {
      recoveryFailure = Self.recoveryReason(for: error)
      errorMessage = "Your saved connection is unavailable. Try again after unlocking the device, or reconnect in Settings."
      diagnostics?.record(source: .auth, severity: .warning, title: "Saved connection unavailable")
      return
    }
    let recoverableSession = (authenticatedConnection?.session).flatMap { current in
      if sessionIsRenewable(current) {
        return current
      }
      return nil
    } ?? (stored?.session).flatMap { current in
      sessionIsValid(current) || sessionIsRenewable(current) ? current : nil
    }
    var progressLeaseID: UUID?
    defer {
      if let progressLeaseID {
        endConnectionProgressLease(progressLeaseID)
      }
    }

    if let recoverableSession {
      guard (try? validateSessionPurpose(recoverableSession)) != nil else {
        session = nil
        let source = DataSourceMode(rawValue: recoverableSession.dataSourceMode) ?? .unknown
        recoveryFailure = .unverifiedSource
        errorMessage = (source == .syntheticDemo ? HealthImportError.previewOnly : .unverifiedSource).localizedDescription
        return
      }
      if let stored { connectionIdentity = stored.identity }
      session = recoverableSession
      if sessionIsValid(recoverableSession) {
        errorMessage = nil
        statusMessage = Self.connectedStatusMessage(for: recoverableSession)
        diagnostics?.record(source: .auth, title: "Connection session restored")
        return
      }

      progressLeaseID = beginConnectionProgressLease()
      if await runCoalescedRenewableRefresh(recoverableSession) {
        return
      }

      // This opportunity ends after an uncertain consuming POST. The next
      // permitted owner can enroll with a fresh challenge; it cannot retry the
      // old refresh credential or restore it as usable auth.
      if committer.hasUnresolvedSubmission { return }
      // Generic signature/counter rejection is terminal for this cycle. Only
      // explicit enrollment/key-required outcomes authorize its fallback.
      if recoveryFailure == .deviceProofRejected { return }
      if session != nil {
        return
      }

      if policy == .backgroundWithReenrollment,
         configurationStore.mode == .hosted,
         sessionStore?.isHostedReenrollmentPending() == true {
        if progressLeaseID == nil {
          progressLeaseID = beginConnectionProgressLease()
        }
        await recoverSubscriptionSession(policy: policy)
        return
      }

      if !policy.allowsInteractiveRecovery {
        return
      }
    }

    if policy == .backgroundWithReenrollment,
       configurationStore.mode == .hosted,
       sessionStore?.isHostedReenrollmentPending() == true {
      if progressLeaseID == nil {
        progressLeaseID = beginConnectionProgressLease()
      }
      await recoverSubscriptionSession(policy: policy)
      return
    }

    if !policy.allowsInteractiveRecovery {
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Background session recovery stopped",
        message: "interactiveRecovery=false renewableCredential=false"
      )
      return
    }

    session = nil
    if progressLeaseID == nil {
      progressLeaseID = beginConnectionProgressLease()
    }

    switch configurationStore.mode {
    case .hosted:
      await runCoalescedSubscriptionOperation {
        await self.recoverSubscriptionSession(policy: policy)
      }
    case .selfHosted:
      await recoverSelfHostedSession()
    }
  }

  /// Re-establishes a hosted session after the backend has explicitly rejected
  /// an otherwise valid session because its subscription entitlement is no
  /// longer active. This deliberately bypasses the normal cache-hit path.
  ///
  /// A successful replacement must mint a different access token; retaining
  /// the existing token after an unsuccessful recovery prevents callers from
  /// retrying a request that the backend has already rejected for entitlement
  /// access.
  func recoverHostedSubscriptionAfterAccessDenied(
    policy: SessionRecoveryPolicy = .foreground,
    policyProvider: SessionRecoveryPolicyProvider? = nil
  ) async -> Bool {
    guard configurationStore.mode == .hosted else {
      return false
    }

    let previousAccessToken = session?.accessToken
    let outcome = await SessionRecoveryContext.$policyProvider.withValue(policyProvider) {
      await SessionRecoveryContext.$current.withValue(SessionRecoveryAttempt()) {
        await recoverSession(policy: policy, forceHostedEnrollment: true)
      }
    }
    guard case .ready = outcome else { return false }

    guard let session,
          session.accessToken != previousAccessToken else {
      return false
    }
    return true
  }

  func setSessionEstablishedHandler(
    _ handler: @escaping @MainActor () -> Void
  ) {
    sessionEstablished = handler
  }

  func clearSessionForConnectionChange() {
    subscriptionOperationID = nil
    subscriptionOperationTask = nil
    renewableRefreshOperationID = nil
    renewableRefreshOperationKey = nil
    renewableRefreshTask = nil
    selfHostedOperationID = nil
    invalidateConnectionProgressGeneration()
    recoveryRequiresActiveSubscription = false
    guard invalidateDurableAuth(replacesOwnership: true) else { return }
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
    diagnostics?.record(source: .auth, title: "Connection session reset")
  }

  @discardableResult
  func clearSessionForAuthenticationFailure(expectedSource: AuthenticatedConnection) -> Bool {
    guard let current = authenticatedConnection, current.identity == expectedSource.identity,
          current.identity.binding == connectionBinding else { return false }
    do {
      guard try AuthOperationJournal.fingerprint(current) == AuthOperationJournal.fingerprint(expectedSource),
            try committer.invalidateIfCurrent(expectedSource, binding: current.identity.binding) else { return false }
      authOwnershipGeneration = UUID()
      incompleteInvalidation = false
      authCommitBlocked = false
      session = nil
      connectionIdentity = nil
      recoveryRequiresActiveSubscription = false
      resetDisconnectedStatus()
      diagnostics?.record(source: .auth, severity: .warning, title: "Connection session expired")
      return true
    } catch {
      incompleteInvalidation = true
      authOwnershipGeneration = UUID()
      authCommitBlocked = true
      session = nil
      connectionIdentity = nil
      errorMessage = AuthCommitError.invalidationIncomplete.localizedDescription
      statusMessage = errorMessage ?? "Disconnection could not be saved."
      diagnostics?.record(source: .auth, severity: .error, title: "Connection invalidation incomplete")
      return false
    }
  }

  /// A successful protected hosted request is authoritative evidence that the
  /// backend entitlement gate is open again. Clear only the subscription
  /// attention state; the device credential itself was never invalid.
  func markHostedSubscriptionAccessRestored() {
    guard configurationStore.mode == .hosted,
          recoveryRequiresActiveSubscription else {
      return
    }

    recoveryRequiresActiveSubscription = false
    diagnostics?.record(source: .auth, title: "Subscription access restored", message: "source=protectedRequest")
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
    let progressLeaseID = beginConnectionProgressLease()
    defer { endConnectionProgressLease(progressLeaseID) }
    let ownershipGeneration = authOwnershipGeneration
    let configurationRevision = expectedConfigurationRevision ?? configurationStore.revision
    attemptedSubscriptionSessionJWSHashes.insert(Self.subscriptionJWSHash(signedTransactionInfo))
    do {
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
    } catch {
      recordSubscriptionConfigurationChange()
      return true
    }

    let previousSession = session
    let hasValidPreviousSession = previousSession.map { sessionIsValid($0) } ?? false
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
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
      diagnostics?.record(
        source: .auth,
        title: "Hosted service warm-up completed",
        message: "elapsedMs=\(elapsedMilliseconds(since: warmupStartedAt))"
      )

      // App Attest permits only one hosted proof operation at a time. A cold-start
      // subscription recovery must let an already-running session refresh finish.
      if let renewableRefreshTask {
        let sharedAttempt = renewableRefreshRecoveryAttempt
        _ = await awaitRenewableRefresh(renewableRefreshTask, operationID: renewableRefreshOperationID)
        sharedAttempt?.replayRequestLinks()
        try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
      }

      let mutationLease = try await committer.acquireLease()
      defer { committer.releaseLease(mutationLease) }
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
      let request = try await makeSubscriptionSessionRequest(
        signedTransactionInfo: signedTransactionInfo,
        configurationRevision: configurationRevision,
        ownershipGeneration: ownershipGeneration
      )
      defer {
        _ = proofProvider.releaseHostedProofOperation(requestId: request.deviceEnrollment.requestId)
      }
      enrollmentKeyId = request.deviceEnrollment.keyId
      enrollmentRequestId = request.deviceEnrollment.requestId
      enrollmentProofKind = request.deviceEnrollment.proofKind
      enrollmentPreparation = request.deviceEnrollment.preparation
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
      guard let binding = connectionBinding else { throw AuthConnectionError.bindingMismatch }
      let source = try committer.enrollmentSource(binding: binding, memory: authenticatedConnection)
      let journalID = try committer.begin(kind: .enrollment, binding: binding, source: source,
        proofRequestID: request.deviceEnrollment.requestId, proofKeyID: request.deviceEnrollment.keyId)
      guard try proofProvider.markHostedEnrollmentSubmissionStarted(
        keyId: request.deviceEnrollment.keyId,
        requestId: request.deviceEnrollment.requestId
      ) else {
        throw SubscriptionEnrollmentStateChangedError()
      }
      try committer.submitted(journalID, binding: binding, source: source)
      enrollmentSubmissionStarted = true
      let sessionRequestStartedAt = Date()
      let createdSession: BackendSessionResponse
      do {
        createdSession = try await createSubscriptionSessionWithTimeout(
          request,
          configurationRevision: configurationRevision,
          journalID: journalID,
          binding: binding,
          ownershipGeneration: ownershipGeneration
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
      // The request completion journals and commits before returning, including
      // confirmed responses arriving after the last sync waiter cancels.
      enrollmentRegistered = true
      guard connectionBinding == binding, isCurrentHostedConfiguration(configurationRevision) else {
        throw SubscriptionConfigurationChangedError()
      }
      guard authenticatedConnection?.session == createdSession else { throw AuthCommitError.commitPending }
      recoveryRequiresActiveSubscription = false
      statusMessage = "PumpSync subscription active"
      diagnostics?.record(source: .auth, title: title)
    } catch {
      timeoutKind = SubscriptionSessionTimeoutKind(error: error)
      guard authOwnershipGeneration == ownershipGeneration else {
        if !enrollmentSubmissionStarted, let keyID = enrollmentKeyId, let requestID = enrollmentRequestId,
           (try? proofProvider.discardUnsubmittedHostedEnrollment(keyId: keyID, requestId: requestID)) == true {
          diagnostics?.record(source: .auth, severity: .warning, title: "Unsubmitted App Attest enrollment discarded",
            message: "reason=connectionModeChanged backendSubmitted=false")
        }
        recordSubscriptionConfigurationChange()
        return true
      }
      recoveryFailure = Self.recoveryReason(for: error)
      blockUnresolvedAuth()
      if Task.isCancelled || error is CancellationError { return false }
      let apiError = error as? APIClientError
      if SessionRecoveryContext.current?.backendCorrelationID == nil, let correlation = apiError?.correlationId {
        SessionRecoveryContext.current?.backendCorrelationID = correlation
      }
      if allowsRejectedAssertionRetry, (error as? AppAttestClientError) == .invalidKey {
        rejectedAssertionRetry = .freshAttestation
      }
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
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Rejected App Attest proof handled",
          message: "protocolVersion=3 proofKind=\(enrollmentProofKind ?? "unknown") preparation=\(enrollmentPreparation?.rawValue ?? "unknown") backendCode=device_proof_rejected localAction=retainKey"
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
                (try? proofProvider.resolveRejectedHostedEnrollment(
                  keyId: enrollmentKeyId,
                  requestId: enrollmentRequestId
                )) == true {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Definitively rejected App Attest enrollment retained",
          message: "protocolVersion=3 proofKind=attestation backendOutcome=definitive localAction=retainKey"
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

      if !committer.hasUnresolvedSubmission, hasValidPreviousSession {
        session = previousSession
      } else {
        session = nil
      }
      if publishesErrors || !hasValidPreviousSession || error is HostedServiceWarmupError {
        let message = error is HostedServiceWarmupError
          ? HostedServiceWarmupError.userMessage
          : subscriptionConnectionMessage(for: safeMessage("PumpSync subscription access could not be verified.", error: error), error: error)
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

    return false
  }

  private func recoverSubscriptionSession(
    policy requestedPolicy: SessionRecoveryPolicy = .foreground,
    missingEntitlementDisposition: MissingEntitlementDisposition = .clearUnusableSession
  ) async {
    var policy: SessionRecoveryPolicy { SessionRecoveryContext.policyProvider?() ?? requestedPolicy }
    let progressLeaseID = beginConnectionProgressLease()
    defer { endConnectionProgressLease(progressLeaseID) }
    let ownershipGeneration = authOwnershipGeneration
    let configurationRevision = configurationStore.revision
    do {
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
    } catch {
      recordSubscriptionRecoveryConfigurationChange()
      return
    }
    let startedAt = Date()
    recoveryRequiresActiveSubscription = false
    diagnostics?.record(source: .auth, title: "Subscription recovery started")
    if policy == .backgroundWithReenrollment {
      diagnostics?.record(
        source: .auth,
        title: "Background App Attest re-enrollment started",
        message: "entitlementSource=cachedStoreKit"
      )
    }

    do {
      let entitlementStartedAt = Date()
      let signedTransactionInfo = try await subscriptionEntitlementJWS(for: policy)
      try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
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
      if session != nil, sessionStore?.isHostedReenrollmentPending() == true {
        try? sessionStore?.clearHostedReenrollmentPending()
        diagnostics?.record(
          source: .auth,
          title: policy == .backgroundWithReenrollment
            ? "Background App Attest re-enrollment completed"
            : "App Attest re-enrollment completed"
        )
      }
      diagnostics?.record(source: .auth, title: "Subscription recovery timing", message: "entitlementMs=\(entitlementMs) totalMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) cacheHit=false")
    } catch StoreKitSubscriptionError.noActiveSubscription {
      guard !Task.isCancelled else { return }
      guard authOwnershipGeneration == ownershipGeneration, isCurrentHostedConfiguration(configurationRevision) else {
        recordSubscriptionRecoveryConfigurationChange()
        return
      }
      recoveryFailure = .missingEntitlement
      let credentialRetained = missingEntitlementDisposition == .preserveRenewableSession
        && session.map { sessionIsRenewable($0) } == true
      if !credentialRetained {
        session = nil
        if !committer.hasUnresolvedSubmission { _ = invalidateDurableAuth() }
      }
      recoveryRequiresActiveSubscription = true
      resetDisconnectedStatus()
      errorMessage = "Your PumpSync subscription could not be verified. Review your subscription to reconnect."
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Subscription access unavailable",
        message: "credentialRetained=\(credentialRetained) policy=\(missingEntitlementDisposition.diagnosticName) retry=nextGrantedTask"
      )
      if policy == .backgroundWithReenrollment {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Background App Attest re-enrollment deferred",
          message: "reason=noCachedEntitlement retry=nextRecovery"
        )
        return
      }
      try? sessionStore?.clearHostedReenrollmentPending()
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Subscription recovery skipped",
        message: "No current StoreKit entitlement was available for subscription recovery."
      )
    } catch {
      if Task.isCancelled || error is CancellationError { return }
      guard authOwnershipGeneration == ownershipGeneration, !(error is SubscriptionConfigurationChangedError),
            isCurrentHostedConfiguration(configurationRevision) else {
        recordSubscriptionRecoveryConfigurationChange()
        return
      }
      recoveryFailure = Self.recoveryReason(for: error)
      if policy != .backgroundWithReenrollment || (error as? APIClientError)?.isAuthenticationFailure == true {
        session = nil
        if !committer.hasUnresolvedSubmission { _ = invalidateDurableAuth() }
      }
      if (error as? APIClientError)?.isAuthenticationFailure == true {
        try? sessionStore?.clearHostedReenrollmentPending()
      }
      resetDisconnectedStatus()
      errorMessage = safeMessage("Your PumpSync subscription could not be checked. Retry Connection to try again.", error: error)
      statusMessage = errorMessage ?? "Connection recovery failed."
      if policy == .backgroundWithReenrollment {
        let reason = (error as? APIClientError)?.hasAmbiguousOutcome == true
          ? "ambiguousBackendOutcome"
          : (error is URLError ? "network" : "unavailable")
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Background App Attest re-enrollment deferred",
          message: "reason=\(reason) retry=nextRecovery"
        )
      }
      diagnostics?.record(error: error, source: .auth, title: "Subscription recovery failed")
    }
  }

  private func subscriptionEntitlementJWS(for requestedPolicy: SessionRecoveryPolicy) async throws -> String {
    var policy: SessionRecoveryPolicy { SessionRecoveryContext.policyProvider?() ?? requestedPolicy }
    do {
      return try await currentEntitlementJWS()
    } catch StoreKitSubscriptionError.noActiveSubscription where policy.allowsInteractiveRecovery {
      diagnostics?.record(
        source: .auth,
        title: "Subscription entitlement cache miss",
        message: "retry=appStoreSync"
      )
      return try await syncedCurrentEntitlementJWS()
    }
  }

  private func recoverSelfHostedSession() async {
    let configurationRevision = configurationStore.revision
    guard isCurrentConfiguration(configurationRevision, mode: .selfHosted),
          configurationStore.apply(to: apiClient) else {
      recoveryFailure = .configurationInvalid
      diagnostics?.record(source: .auth, severity: .warning, title: "Self-hosted recovery skipped", message: "No valid self-hosted service URL is configured.")
      return
    }

    let operationID = UUID()
    selfHostedOperationID = operationID
    let progressLeaseID = beginConnectionProgressLease()
    defer { endConnectionProgressLease(progressLeaseID) }
    errorMessage = nil
    statusMessage = "Connecting to self-hosted service..."
    diagnostics?.record(source: .auth, title: "Self-hosted recovery started")

    do {
      let mutationLease = try await committer.acquireLease()
      defer { committer.releaseLease(mutationLease) }
      let request = try await makeSelfHostedSessionRequest(
        configurationRevision: configurationRevision,
        operationID: operationID
      )
      try prepareSelfHostedRequest(configurationRevision: configurationRevision, operationID: operationID)
      guard let binding = connectionBinding else { throw AuthConnectionError.bindingMismatch }
      let source = try committer.enrollmentSource(binding: binding, memory: authenticatedConnection)
      let journalID = try committer.begin(kind: .enrollment, binding: binding, source: source,
        proofRequestID: request.deviceEnrollment.requestId, proofKeyID: nil)
      try committer.submitted(journalID, binding: binding, source: source)
      let createdSession = try await createSelfHostedSession(request)
      guard isCurrentConfiguration(configurationRevision, mode: .selfHosted), selfHostedOperationID == operationID,
            connectionBinding == binding else { throw BackendConfigurationChangedError() }
      let committed = try committer.receive(createdSession, operationID: journalID, binding: binding, proofProvider: proofProvider)
      publishCommitted(committed)
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
      if Task.isCancelled || error is CancellationError {
        finishSelfHostedOperation(operationID)
        return
      }
      recoveryFailure = Self.recoveryReason(for: error)
      blockUnresolvedAuth()
      resetDisconnectedStatus()
      errorMessage = safeMessage("The self-hosted connection could not be restored. Retry Connection or review Connection Settings.", error: error)
      statusMessage = errorMessage ?? "Connection recovery failed."
      diagnostics?.record(error: error, source: .auth, title: "Self-hosted recovery failed")
    }

    finishSelfHostedOperation(operationID)
  }

  private func makeSubscriptionSessionRequest(
    signedTransactionInfo: String,
    configurationRevision: Int,
    ownershipGeneration: UUID
  ) async throws -> SubscriptionSessionRequest {
    let requestHash = DeviceSessionProofProvider.base64URL(
      Self.subscriptionJWSHash(signedTransactionInfo)
    )
    try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
    let challengeStartedAt = Date()
    let challenge = try await createSessionChallenge(SessionChallengeRequest(
      installationId: configurationStore.installationId,
      purpose: "hostedEnrollment",
      requestHash: requestHash
    ))
    try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
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
    guard let sourceConnection = authenticatedConnection, sourceConnection.session == currentSession else { return false }
    let configurationRevision = configurationStore.revision
    let mode = configurationStore.mode
    do {
      try prepareConfiguredRequest(configurationRevision: configurationRevision, mode: mode)
    } catch {
      recordRefreshConfigurationChange()
      return false
    }
    let ownershipGeneration = authOwnershipGeneration
    let startedAt = Date()
    diagnostics?.record(
      source: .auth,
      title: "Renewable session refresh started",
      message: "protocolVersion=3 serviceMode=\(currentSession.serviceMode)"
    )
    do {
      let mutationLease = try await committer.acquireLease()
      defer { committer.releaseLease(mutationLease) }
      guard authenticatedConnection == sourceConnection, connectionBinding == sourceConnection.identity.binding else {
        throw AuthConnectionError.sourceReplaced
      }
      let proofKind = mode == .hosted ? "appAttest" : "secureEnclaveP256"
      let proofStartedAt = Date()
      diagnostics?.record(
        source: .auth,
        title: "Renewable session proof preparation started",
        message: "serviceMode=\(currentSession.serviceMode) proofKind=\(proofKind)"
      )
      let request: SessionRefreshRequest
      do {
        request = try await proofProvider.refreshRequest(
          session: currentSession,
          installationId: configurationStore.installationId,
          mode: mode
        )
        diagnostics?.record(
          source: .auth,
          title: "Renewable session proof prepared",
          message: "serviceMode=\(currentSession.serviceMode) proofKind=\(proofKind) elapsedMs=\(elapsedMilliseconds(since: proofStartedAt))"
        )
      } catch {
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Renewable session proof preparation failed",
          message: "serviceMode=\(currentSession.serviceMode) proofKind=\(proofKind) reason=\(renewableRefreshFailureReason(error)) elapsedMs=\(elapsedMilliseconds(since: proofStartedAt))"
        )
        throw error
      }
      defer {
        if mode == .hosted {
          _ = proofProvider.releaseHostedProofOperation(requestId: request.requestId)
        }
      }
      try prepareConfiguredRequest(configurationRevision: configurationRevision, mode: mode)
      try Task.checkCancellation()
      guard authenticatedConnection == sourceConnection, connectionBinding == sourceConnection.identity.binding else {
        throw AuthConnectionError.sourceReplaced
      }
      let journalID = try committer.begin(kind: .refresh, binding: sourceConnection.identity.binding, source: sourceConnection,
        proofRequestID: request.requestId, proofKeyID: mode == .hosted ? try proofProvider.hostedProofKeyID(requestId: request.requestId) : nil)
      try committer.submitted(journalID, binding: sourceConnection.identity.binding, source: sourceConnection)
      let requestStartedAt = Date()
      diagnostics?.record(
        source: .auth,
        title: "Renewable session request started",
        message: "serviceMode=\(currentSession.serviceMode)"
      )
      let refreshed: BackendSessionResponse
      do {
        SessionRecoveryContext.current?.backendCorrelationID = nil
        refreshed = try await apiClient.refreshSession(request, mode: mode, backendCorrelation: { SessionRecoveryContext.current?.backendCorrelationID = $0 })
        diagnostics?.record(
          source: .auth,
          title: "Renewable session request completed",
          message: "serviceMode=\(currentSession.serviceMode) outcome=success elapsedMs=\(elapsedMilliseconds(since: requestStartedAt))"
        )
      } catch {
        if SessionRecoveryContext.current?.backendCorrelationID == nil, let correlation = (error as? APIClientError)?.correlationId {
          SessionRecoveryContext.current?.backendCorrelationID = correlation
        }
        if let apiError = error as? APIClientError, !apiError.hasAmbiguousOutcome {
          try committer.rejectDefinitively(journalID, binding: sourceConnection.identity.binding)
        }
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "Renewable session request completed",
          message: "serviceMode=\(currentSession.serviceMode) outcome=failure reason=\(renewableRefreshFailureReason(error)) elapsedMs=\(elapsedMilliseconds(since: requestStartedAt))"
        )
        throw error
      }
      try prepareConfiguredRequest(configurationRevision: configurationRevision, mode: mode)
      guard refreshed.protocolVersion == 3, refreshed.serviceMode == currentSession.serviceMode else {
        throw APIClientError.invalidResponse
      }
      guard isCurrentRefreshSource(currentSession), authenticatedConnection == sourceConnection else {
        diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh stopped",
          message: "reason=sessionSuperseded"
        )
        return isSignedIn
      }

      let committed = try committer.receive(refreshed, operationID: journalID, binding: sourceConnection.identity.binding, proofProvider: proofProvider)
      publishCommitted(committed)
      errorMessage = nil
      statusMessage = Self.connectedStatusMessage(for: refreshed)
      diagnostics?.record(
        source: .auth,
        title: "Renewable session refresh completed",
        message: "protocolVersion=3 elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
      )
      return true
    } catch {
      guard authOwnershipGeneration == ownershipGeneration else {
        recordRefreshConfigurationChange()
        return false
      }
      recoveryFailure = Self.recoveryReason(for: error)
      blockUnresolvedAuth()
      if committer.hasUnresolvedSubmission {
        errorMessage = safeMessage("Your connection needs secure recovery. Retry after unlocking the device.", error: error)
        statusMessage = errorMessage ?? "Connection recovery deferred."
        return false
      }
      if Task.isCancelled || error is CancellationError {
        guard isCurrentRefreshSource(currentSession), authenticatedConnection == sourceConnection else {
          diagnostics?.record(
            source: .auth,
            title: "Renewable session refresh stopped",
            message: "reason=sessionSuperseded"
          )
          return isSignedIn
        }
        session = currentSession
        diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh stopped",
          message: "reason=cancelled"
        )
        return false
      }
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
      guard isCurrentRefreshSource(currentSession), authenticatedConnection == sourceConnection else {
        diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh stopped",
          message: "reason=sessionSuperseded"
        )
        return isSignedIn
      }
      if mode == .hosted, (error as? APIClientError)?.isDeviceKeyReenrollmentRequired == true {
        session = nil
        _ = invalidateDurableAuth()
        _ = try? proofProvider.discardRegisteredHostedKey()
        try? sessionStore?.markHostedReenrollmentPending()
        diagnostics?.record(
          source: .auth,
          severity: .warning,
          title: "App Attest key re-enrollment required",
          message: "backendCode=device_key_reenrollment_required localAction=discardKey retry=background"
        )
        return false
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
        _ = invalidateDurableAuth()
        if mode == .hosted, invalidAppAttestKey { try? sessionStore?.markHostedReenrollmentPending() }
      } else {
        session = currentSession
      }
      diagnostics?.record(
        source: .auth,
        severity: .warning,
        title: "Renewable session refresh failed",
        message: "permanentlyRejected=\(permanentlyRejected) elapsedMs=\(Int(Date().timeIntervalSince(startedAt) * 1_000)) error=\(safeMessage("refresh failed", error: error))"
      )
      errorMessage = safeMessage("Your secure connection could not be restored. Retry Connection to try again.", error: error)
      statusMessage = errorMessage ?? "Connection recovery failed."
      return false
    }
  }

  private func runCoalescedRenewableRefresh(_ source: BackendSessionResponse) async -> Bool {
    let key = RenewableRefreshOperationKey(
      configurationRevision: configurationStore.revision,
      mode: configurationStore.mode,
      sessionFamilyId: source.sessionFamilyId,
      refreshToken: source.refreshToken,
      connectionId: authenticatedConnection?.identity.id
    )
    if let renewableRefreshTask,
       renewableRefreshOperationKey == key {
      if renewableRefreshTask.isCancelled {
        self.renewableRefreshTask = nil
        self.renewableRefreshOperationID = nil
        self.renewableRefreshOperationKey = nil
        diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh discarded",
          message: "reason=cancelledOperation"
        )
      } else {
        diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh coalesced",
          message: "coalesced=true"
        )
        let attempt = renewableRefreshRecoveryAttempt
        let result = await awaitRenewableRefresh(renewableRefreshTask, operationID: renewableRefreshOperationID)
        attempt?.replayRequestLinks()
        recoveryFailure = attempt?.failure
        SessionRecoveryContext.current?.backendCorrelationID = attempt?.backendCorrelationID
        return result
      }
    }

    let operationID = UUID()
    let attempt = SessionRecoveryContext.current ?? SessionRecoveryAttempt()
    renewableRefreshRecoveryAttempt = attempt
    let diagnosticContext = SyncDiagnosticContext.current
    let task = Task { @MainActor [weak self] in
      guard let self else {
        return false
      }
      let result = await SyncDiagnosticContext.$current.withValue(diagnosticContext) {
        await SessionRecoveryContext.$current.withValue(attempt) { await self.refreshRenewableSession(source) }
      }
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
    return await awaitRenewableRefresh(task, operationID: operationID)
  }

  private func awaitRenewableRefresh(
    _ task: Task<Bool, Never>,
    operationID: UUID?
  ) async -> Bool {
    guard let operationID else { return false }
    let waiterID = UUID()
    renewableRefreshWaiters[operationID, default: []].insert(waiterID)
    defer { removeRefreshWaiter(waiterID, operationID: operationID) }
    return await withTaskCancellationHandler(operation: {
      let result = await task.value
      return Task.isCancelled ? false : result
    }, onCancel: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.removeRefreshWaiter(waiterID, operationID: operationID)
        guard self.renewableRefreshOperationID == operationID,
              self.renewableRefreshWaiters[operationID] == nil else {
          return
        }
        task.cancel()
        self.renewableRefreshTask = nil
        self.renewableRefreshOperationID = nil
        self.renewableRefreshOperationKey = nil
        self.diagnostics?.record(
          source: .auth,
          title: "Renewable session refresh discarded",
          message: "reason=cancelledWaiter"
        )
      }
    })
  }

  private func removeRefreshWaiter(_ waiterID: UUID, operationID: UUID) {
    renewableRefreshWaiters[operationID]?.remove(waiterID)
    if renewableRefreshWaiters[operationID]?.isEmpty == true { renewableRefreshWaiters[operationID] = nil }
  }

  private func isCurrentRefreshSource(_ source: BackendSessionResponse) -> Bool {
    guard let current = session else {
      return false
    }
    return current.protocolVersion == source.protocolVersion
      && current.serviceMode == source.serviceMode
      && current.sessionFamilyId == source.sessionFamilyId
      && current.refreshToken == source.refreshToken
      && current.accessToken == source.accessToken
  }

  private func resetDisconnectedStatus() {
    errorMessage = nil
    statusMessage = "Connect to PumpSync or a self-hosted service"
  }

  private func runQueuedExplicitSubscriptionOperation(
    _ operation: @escaping @MainActor () async -> Void
  ) async {
    let progressLeaseID = beginConnectionProgressLease()
    defer { endConnectionProgressLease(progressLeaseID) }
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
    guard !Task.isCancelled else { return false }
    if subscriptionOperationTask?.isCancelled == true {
      subscriptionOperationTask = nil
      subscriptionOperationID = nil
    }
    if let subscriptionOperationTask {
      diagnostics?.record(source: .auth, title: "Subscription operation coalesced", message: "coalesced=true")
      let attempt = subscriptionRecoveryAttempt
      await awaitSubscriptionOperation(subscriptionOperationTask, operationID: subscriptionOperationID)
      attempt?.replayRequestLinks()
      recoveryFailure = attempt?.failure
      if let correlation = attempt?.backendCorrelationID { SessionRecoveryContext.current?.backendCorrelationID = correlation }
      return false
    }

    let operationID = UUID()
    let attempt = SessionRecoveryContext.current ?? SessionRecoveryAttempt()
    subscriptionRecoveryAttempt = attempt
    let diagnosticContext = SyncDiagnosticContext.current
    let task = Task { @MainActor [weak self] in
      await SyncDiagnosticContext.$current.withValue(diagnosticContext) {
        await SessionRecoveryContext.$current.withValue(attempt) { await operation() }
      }
      guard self?.subscriptionOperationID == operationID else {
        return
      }
      self?.subscriptionOperationTask = nil
      self?.subscriptionOperationID = nil
    }
    subscriptionOperationID = operationID
    subscriptionOperationTask = task
    await awaitSubscriptionOperation(task, operationID: operationID)
    return true
  }

  private func awaitSubscriptionOperation(_ task: Task<Void, Never>, operationID: UUID?) async {
    guard let operationID else { return }
    let waiterID = UUID()
    subscriptionWaiters[operationID, default: []].insert(waiterID)
    defer { removeSubscriptionWaiter(waiterID, operationID: operationID) }
    await withTaskCancellationHandler(operation: { await task.value }, onCancel: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.removeSubscriptionWaiter(waiterID, operationID: operationID)
        if self.subscriptionOperationID == operationID, self.subscriptionWaiters[operationID] == nil {
          task.cancel()
        }
      }
    })
  }

  private func removeSubscriptionWaiter(_ waiterID: UUID, operationID: UUID) {
    subscriptionWaiters[operationID]?.remove(waiterID)
    if subscriptionWaiters[operationID]?.isEmpty == true { subscriptionWaiters[operationID] = nil }
  }

  private func createSubscriptionSessionWithTimeout(
    _ request: SubscriptionSessionRequest,
    configurationRevision: Int,
    journalID: UUID,
    binding: AuthConnectionBinding,
    ownershipGeneration: UUID
  ) async throws -> BackendSessionResponse {
    let race = SubscriptionRequestRace()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        race.continuation = continuation
        if Task.isCancelled {
          race.finish(.failure(CancellationError()))
          return
        }
        race.backendTask = Task { @MainActor in
          do {
            try prepareHostedRequest(configurationRevision: configurationRevision, ownershipGeneration: ownershipGeneration)
            try committer.validateSubmitted(journalID, binding: binding)
            let response = try await createSubscriptionSession(request)
            guard isCurrentHostedConfiguration(configurationRevision), connectionBinding == binding else {
              throw SubscriptionConfigurationChangedError()
            }
            let committed = try committer.receive(response, operationID: journalID, binding: binding, proofProvider: proofProvider)
            publishCommitted(committed)
            race.finish(.success(response))
          } catch {
            if let apiError = error as? APIClientError, !apiError.hasAmbiguousOutcome {
              try? committer.rejectDefinitively(journalID, binding: binding)
            }
            race.finish(.failure(error))
          }
        }

        race.timeoutTask = Task { @MainActor in
          do {
            try await Task.sleep(for: .seconds(subscriptionSessionTimeout))
          } catch {
            return
          }
          race.finish(.failure(SubscriptionSessionTimeoutError()))
        }
      }
    }, onCancel: {
      Task { @MainActor in race.finish(.failure(CancellationError())) }
    })
  }

  private func preserveValidSessionOrClear() {
    if let session, sessionIsValid(session) {
      return
    }
    session = nil
    _ = invalidateDurableAuth()
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
    if let error = error as? HealthImportError { return error.localizedDescription }
    guard let localizedError = error as? LocalizedError, let description = localizedError.errorDescription else {
      return fallback
    }

    return DiagnosticsLogStore.redacted(description)
  }

  private func elapsedMilliseconds(since startedAt: Date) -> Int {
    Int(Date().timeIntervalSince(startedAt) * 1_000)
  }

  private func renewableRefreshFailureReason(_ error: Error) -> String {
    if Task.isCancelled || error is CancellationError {
      return "cancelled"
    }
    if let urlError = error as? URLError {
      return urlError.code == .timedOut ? "timeout" : "network"
    }
    if case .appAttestTimedOut? = error as? DeviceSessionProofError {
      return "timeout"
    }
    if let apiError = error as? APIClientError {
      if apiError.isAuthenticationFailure {
        return "authentication"
      }
      if apiError.isRateLimited {
        return "rateLimited"
      }
      if apiError.hasAmbiguousOutcome {
        return "backendUnavailable"
      }
      return "backendRejected"
    }
    switch error as? AppAttestClientError {
    case .serverUnavailable:
      return "appAttestUnavailable"
    case .invalidKey:
      return "invalidAppAttestKey"
    case .nonRetryable:
      return "appAttestRejected"
    case nil:
      return "unavailable"
    }
  }

  private static func recoveryReason(for error: Error) -> SessionRecoveryReason {
    switch error as? AuthCommitError {
    case .uncertainSubmission: return .uncertainSubmission
    case .commitPending: return .commitPending
    case .invalidationIncomplete: return .invalidationIncomplete
    case .operationReplaced, .proofStateReplaced: return .connectionReplaced
    case nil: break
    }
    switch error as? DeviceSessionProofError {
    case .appAttestUnavailable: return .appAttestUnavailable
    case .appAttestTimedOut: return .appAttestTimedOut
    case .hostedProofOperationInProgress: return .proofOperationInProgress
    case .secureEnclaveUnavailable: return .appAttestUnavailable
    case .missingRenewableCredential: return .interactiveRecoveryRequired
    case nil: break
    }
    switch error as? AppAttestClientError {
    case .serverUnavailable: return .appAttestUnavailable
    case .invalidKey: return .invalidDeviceKey
    case .nonRetryable: return .backendRejected
    case nil: break
    }
    if error is URLError || error is HostedServiceWarmupError || error is SubscriptionSessionTimeoutError { return .networkUnavailable }
    if let api = error as? APIClientError {
      if api.isDeviceProofRejected { return .deviceProofRejected }
      return api.hasAmbiguousOutcome ? .networkUnavailable : (api.isAuthenticationFailure ? .authenticationRejected : .backendRejected)
    }
    if error is HealthImportError { return .unverifiedSource }
    switch error as? AuthConnectionError {
    case .bindingMismatch: return .configurationInvalid
    case .sourceReplaced: return .connectionReplaced
    case nil: break
    }
    return .storageUnavailable
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

  private func prepareHostedRequest(configurationRevision: Int, ownershipGeneration: UUID? = nil) throws {
    try Task.checkCancellation()
    guard ownershipGeneration == nil || ownershipGeneration == authOwnershipGeneration else {
      throw SubscriptionConfigurationChangedError()
    }
    guard isCurrentHostedConfiguration(configurationRevision),
          configurationStore.apply(to: apiClient) else {
      throw SubscriptionConfigurationChangedError()
    }
  }

  private func prepareSelfHostedRequest(configurationRevision: Int, operationID: UUID) throws {
    try Task.checkCancellation()
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

  private func subscriptionConnectionMessage(for message: String, error: Error? = nil) -> String {
    if let error, (error as? APIClientError)?.backendCode != "invalid_app_store_transaction" {
      return message
    }
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

@MainActor
private final class SubscriptionRequestRace {
  var continuation: CheckedContinuation<BackendSessionResponse, Error>?
  var backendTask: Task<Void, Never>?
  var timeoutTask: Task<Void, Never>?

  func finish(_ result: Result<BackendSessionResponse, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    backendTask?.cancel()
    timeoutTask?.cancel()
    backendTask = nil
    timeoutTask = nil
    continuation.resume(with: result)
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
    try? installSession(BackendSessionResponse(
      accessToken: "screenshot-access-token",
      expiresAt: Date().addingTimeInterval(60 * 60),
      serviceMode: serviceMode,
      dataSourceMode: "tandemSource"
    ), installation: .enrollment)
    statusMessage = serviceMode == "hosted" ? "PumpSync subscription active" : "Connected to self-hosted service"
    errorMessage = nil
  }
}
#endif
