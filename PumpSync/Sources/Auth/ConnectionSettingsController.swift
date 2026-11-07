import Foundation
import Observation

struct SubscriptionConnectionRequest: Identifiable {
  let id: UUID
  let auth: AuthService
  let namespace: UUID?
}

@MainActor
@Observable
final class ConnectionSettingsController {
  var mode: BackendAccessMode
  var serverURL: String
  private(set) var candidateAuth: AuthService?
  private(set) var isConnecting = false
  private(set) var feedback: String?
  private let configuration: BackendConfigurationStore
  private let liveAuth: AuthService
  private let liveAPI: PumpSyncAPIClient
  private let sync: SyncCoordinator
  private let storage: ConnectionActivationStorage
  private let diagnostics: DiagnosticsLogStore
  private var candidate: ConnectionActivationStorage.Candidate?
  private var candidateConfiguration: BackendConfigurationStore?
  private var generation = UUID()
  private var ownsReplacement = false
  private var inFlight = false
  private var canceledNamespaces = Set<UUID>()
  typealias CandidateFactory = @MainActor (PumpSyncAPIClient, BackendConfigurationStore, any BackendSessionPersistence, DiagnosticsLogStore) -> AuthService
  private let makeCandidate: CandidateFactory

  init(configuration: BackendConfigurationStore, auth: AuthService, api: PumpSyncAPIClient,
       sync: SyncCoordinator, storage: ConnectionActivationStorage, diagnostics: DiagnosticsLogStore,
       makeCandidate: CandidateFactory? = nil) {
    self.makeCandidate = makeCandidate ?? { api, configuration, persistence, diagnostics in
      AuthService(apiClient: api, configurationStore: configuration,
        sessionStore: BackendSessionStore(keychain: persistence),
        proofProvider: DeviceSessionProofProvider(keychain: persistence, diagnostics: diagnostics), diagnostics: diagnostics)
    }
    self.configuration = configuration
    liveAuth = auth
    liveAPI = api
    self.sync = sync
    self.storage = storage
    self.diagnostics = diagnostics
    mode = configuration.mode
    serverURL = configuration.selfHostedBaseURLString
  }

  var hasChanges: Bool { mode != configuration.mode || (mode == .selfHosted && serverURL != configuration.selfHostedBaseURLString) }
  var canConnect: Bool { !isConnecting && !inFlight && !sync.hasActiveSyncExecution && !liveAuth.isConnecting && !liveAuth.isReplacingConnection }
  var connectionDescription: String {
    if isConnecting { return candidateAuth?.statusMessage ?? liveAuth.statusMessage }
    if let feedback { return feedback }
    if hasChanges { return "Changes take effect only after connection succeeds. Your current setup remains active." }
    return liveAuth.isSignedIn ? liveAuth.statusMessage : "Choose a service and connect."
  }

  func cancel() {
    generation = UUID()
    if let candidate {
      canceledNamespaces.insert(candidate.namespace)
      try? storage.abandon(candidate.namespace)
      if candidateAuth?.isConnecting != true && !inFlight { try? storage.discardIfInactive(candidate.namespace) }
    }
    candidateAuth = nil
    candidate = nil
    candidateConfiguration = nil
    isConnecting = false
    if ownsReplacement { liveAuth.endConnectionReplacement(activated: false) }
    ownsReplacement = false
    mode = configuration.mode
    serverURL = configuration.selfHostedBaseURLString
    feedback = nil
  }

  /// The caller holds this candidate while presenting Apple's purchase sheet.
  /// A canceled purchase only releases the live replacement fence.
  func prepareSubscription() -> SubscriptionConnectionRequest? {
    guard canConnect else { return nil }
    if mode == configuration.mode && mode == .hosted {
      generation = UUID()
      candidateAuth = liveAuth
      return SubscriptionConnectionRequest(id: generation, auth: liveAuth, namespace: nil)
    }
    guard let auth = prepare() else { return nil }
    return SubscriptionConnectionRequest(id: generation, auth: auth, namespace: candidate?.namespace)
  }

  func connect() async {
    guard canConnect else { return }
    if !hasChanges {
      inFlight = true
      isConnecting = true
      let submitted = generation
      defer { inFlight = false; isConnecting = false }
      if mode == .hosted { await liveAuth.connectUsingCurrentSubscription() }
      else { await liveAuth.connectSelfHosted() }
      guard submitted == generation else { return }
      feedback = liveAuth.errorMessage ?? liveAuth.statusMessage
      return
    }
    guard let auth = prepare() else { return }
    inFlight = true
    defer { inFlight = false }
    let submitted = generation
    let submittedNamespace = candidate?.namespace
    defer {
      if submitted != generation, let submittedNamespace { try? storage.discardIfInactive(submittedNamespace) }
    }
    if mode == .hosted || !auth.isSignedIn {
      if mode == .hosted { await auth.connectUsingCurrentSubscription() }
      else { await auth.connectSelfHosted() }
    }
    guard submitted == generation else { return }
    finish()
  }

  func finishSubscription(_ request: SubscriptionConnectionRequest, verified: Bool) {
    guard request.id == generation else {
      if let namespace = request.namespace, !request.auth.isConnecting { try? storage.discardIfInactive(namespace) }
      return
    }
    if verified {
      if ownsReplacement { finish() }
    } else if ownsReplacement {
      cancel()
    }
    candidateAuth = nil
  }

  func subscriptionAttemptFinished(_ request: SubscriptionConnectionRequest) {
    guard request.id != generation, let namespace = request.namespace else { return }
    try? storage.discardIfInactive(namespace)
  }

  private func prepare() -> AuthService? {
    guard canConnect, liveAuth.beginConnectionReplacement() else {
      feedback = "Wait for the current sync or connection to finish."
      return nil
    }
    ownsReplacement = true
    generation = UUID()
    feedback = nil
    var draft = BackendConnectionDraft(configuration: configuration)
    draft.mode = mode
    if mode == .selfHosted {
      guard let url = BackendConfigurationStore.validatedSelfHostedURL(from: serverURL) else {
        feedback = "Enter an HTTPS API URL ending in /api, without a username, password, query, or fragment. HTTP is allowed only for localhost."
        release()
        return nil
      }
      draft.serverURL = url.absoluteString
    }
    do {
      let pending = try storage.prepare(draft, excluding: canceledNamespaces, installationId: configuration.installationId)
      let configuration = BackendConfigurationStore.candidate(pending.draft, installationId: configuration.installationId)
      let api = PumpSyncAPIClient(baseURL: configuration.selectedBaseURL!, urlSession: liveAPI.urlSession, maxRetryCount: liveAPI.maxRetryCount)
      let auth = makeCandidate(api, configuration, pending.persistence, diagnostics)
      candidate = pending
      candidateConfiguration = configuration
      candidateAuth = auth
      isConnecting = true
      return auth
    } catch {
      feedback = "Connection changes could not be prepared. Your current setup is unchanged."
      diagnostics.record(source: .auth, severity: .error, title: "Connection changes unavailable")
      release()
      return nil
    }
  }

  private func finish() {
    guard let auth = candidateAuth, var pending = candidate, let candidateConfiguration else { release(); return }
    guard auth.isSignedIn else {
      feedback = auth.errorMessage ?? "The new connection was not activated. Your current setup is unchanged."
      release()
      return
    }
    // Purchase verification may route hosted traffic by the signed StoreKit environment.
    pending.draft = BackendConnectionDraft(configuration: candidateConfiguration)
    guard !sync.hasActiveSyncExecution else {
      feedback = "Wait for the current sync to finish, then connect again."
      release()
      return
    }
    do {
      try storage.activate(pending, configuration: configuration)
      _ = configuration.apply(to: liveAPI)
      liveAuth.endConnectionReplacement(activated: true)
      ownsReplacement = false
      mode = configuration.mode
      serverURL = configuration.selfHostedBaseURLString
      feedback = liveAuth.isSignedIn ? "Connected." : "Connection saved. Unlock your device and reconnect if needed."
      diagnostics.record(source: .auth, title: "Connection changes activated")
    } catch {
      feedback = "Connection changes could not be saved. Your current setup is unchanged."
      release()
    }
    isConnecting = false
    candidateAuth = nil
    candidate = nil
    self.candidateConfiguration = nil
  }

  private func release() {
    if ownsReplacement { liveAuth.endConnectionReplacement(activated: false) }
    ownsReplacement = false
    isConnecting = false
    candidateAuth = nil
    candidate = nil
    candidateConfiguration = nil
  }
}
