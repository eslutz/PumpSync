import Foundation

struct BackendConnectionDraft: Codable, Equatable {
  var mode: BackendAccessMode
  var serverURL: String
  var hostedEnvironment: HostedSubscriptionEnvironment

  init(mode: BackendAccessMode, serverURL: String, hostedEnvironment: HostedSubscriptionEnvironment) {
    self.mode = mode
    self.serverURL = serverURL
    self.hostedEnvironment = hostedEnvironment
  }

  @MainActor init(configuration: BackendConfigurationStore) {
    self.init(mode: configuration.mode, serverURL: configuration.selfHostedBaseURLString, hostedEnvironment: configuration.hostedEnvironment)
  }

  @MainActor func apply(to configuration: BackendConfigurationStore) {
    configuration.selfHostedBaseURLString = serverURL
    configuration.selectHostedEnvironment(hostedEnvironment)
    configuration.mode = mode
  }
}

/// Separate storage for a candidate's proof keys, renewable session and auth journal.
/// The live router changes only when a single device-only Keychain pointer commits.
@MainActor
final class ConnectionActivationStorage: BackendSessionPersistence {
  private struct Record: Codable {
    let namespace: UUID
    let draft: BackendConnectionDraft
    var retiredNamespaces: [UUID]? = nil
  }

  struct Candidate {
    let namespace: UUID
    var draft: BackendConnectionDraft
    let persistence: any BackendSessionPersistence
  }

  private static let activeKey = "backend.connection.active.v1"
  private static let pendingKey = "backend.connection.pending.v1"
  private static let abandonedKey = "backend.connection.abandoned.v1"
  private static let legacyNamespace = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
  private static let authAccounts = ["backend.session.current", "backend.session.hosted-reenrollment-pending", "backend.auth.operation-journal.v1", "backend.auth.invalidation.v1", "backend.auth.invalidation-fallback.v1", "device-proof.secure-enclave-p256.v1", "device-proof.app-attest-state.v4"]
  private let root: any BackendSessionPersistence

  init(root: any BackendSessionPersistence) { self.root = root }

  private func record(_ key: String) throws -> Record? {
    try root.readData(account: key).map { try JSONCodec.decoder.decode(Record.self, from: $0) }
  }

  func restoreConfiguration(_ configuration: BackendConfigurationStore, apiClient: PumpSyncAPIClient? = nil) throws {
    cleanupAbandoned()
    guard let active = try record(Self.activeKey) else {
      if let apiClient { _ = configuration.apply(to: apiClient) }
      return
    }
    let draft = try recoveredDraft(active.draft, namespace: active.namespace, installationId: configuration.installationId)
    draft.apply(to: configuration)
    if let apiClient { _ = configuration.apply(to: apiClient) }
    cleanupRetired()
  }

  private func recoveredDraft(_ draft: BackendConnectionDraft, namespace: UUID, installationId: String?) throws -> BackendConnectionDraft {
    let persistence = ScopedConnectionPersistence(root: root, namespace: namespace)
    let journal = try BackendSessionStore(keychain: persistence).loadAuthJournal()
    var binding: AuthConnectionBinding?
    // The journal is durable BEFORE a consuming POST. Never restore an older
    // route and let AuthSessionCommitter discard an unresolved new-route POST.
    if let journal, journal.phase != .prepared || journal.inheritedUncertainty != nil {
      binding = journal.binding
    } else if let data = try persistence.readData(account: "backend.session.current") {
      binding = try JSONCodec.decoder.decode(StoredAuthConnection.self, from: data).identity?.binding
    }
    guard let binding else { return draft }
    guard binding.mode == draft.mode, installationId == nil || binding.installationId == installationId,
          binding.purpose == .liveImport else { throw AuthConnectionError.bindingMismatch }
    var restored = draft
    if binding.mode == .hosted {
      if binding.backendIdentity == ImportSessionSnapshot.canonicalBackendIdentity(AppConstants.hostedAPIBaseURL(for: .sandbox)) { restored.hostedEnvironment = .sandbox }
      else if binding.backendIdentity == ImportSessionSnapshot.canonicalBackendIdentity(AppConstants.hostedAPIBaseURL(for: .production)) { restored.hostedEnvironment = .production }
      else { throw AuthConnectionError.bindingMismatch }
    } else {
      guard let url = BackendConfigurationStore.validatedSelfHostedURL(from: draft.serverURL),
            ImportSessionSnapshot.canonicalBackendIdentity(url) == binding.backendIdentity else { throw AuthConnectionError.bindingMismatch }
    }
    return restored
  }

  func prepare(_ draft: BackendConnectionDraft, excluding: Set<UUID> = [], installationId: String? = nil) throws -> Candidate {
    // Retain the same candidate journal on retry, including uncertain POSTs.
    let previous = try record(Self.pendingKey)
    let active = try record(Self.activeKey)
    let reusesPending = previous.map {
      $0.draft.mode == draft.mode && $0.draft.serverURL == draft.serverURL
        && (draft.mode == .hosted || $0.draft.hostedEnvironment == draft.hostedEnvironment)
        && $0.namespace != active?.namespace && !excluding.contains($0.namespace)
    } == true
    if let previous, !reusesPending, previous.namespace != active?.namespace, !excluding.contains(previous.namespace) {
      try removeNamespace(previous.namespace)
    }
    let namespace = reusesPending ? previous!.namespace : UUID()
    let restored = try recoveredDraft(draft, namespace: namespace, installationId: installationId)
    let pending = Record(namespace: namespace, draft: restored)
    try root.writeData(try JSONCodec.encoder.encode(pending), account: Self.pendingKey)
    return Candidate(namespace: namespace, draft: restored, persistence: ScopedConnectionPersistence(root: root, namespace: namespace))
  }

  func abandon(_ namespace: UUID) throws {
    var queued = try abandonedNamespaces()
    if !queued.contains(namespace) { queued.append(namespace) }
    try root.writeData(try JSONCodec.encoder.encode(queued), account: Self.abandonedKey)
    if try record(Self.pendingKey)?.namespace == namespace { try root.delete(account: Self.pendingKey) }
  }

  func discardIfInactive(_ namespace: UUID) throws {
    guard try record(Self.activeKey)?.namespace != namespace,
          try record(Self.pendingKey)?.namespace != namespace else { return }
    try removeNamespace(namespace)
    let remaining = try abandonedNamespaces().filter { $0 != namespace }
    try root.writeData(try JSONCodec.encoder.encode(remaining), account: Self.abandonedKey)
  }

  private func abandonedNamespaces() throws -> [UUID] {
    try root.readData(account: Self.abandonedKey).map { try JSONCodec.decoder.decode([UUID].self, from: $0) } ?? []
  }

  private func cleanupAbandoned() {
    guard let queued = try? abandonedNamespaces() else { return }
    for namespace in queued { try? discardIfInactive(namespace) }
  }

  func activate(_ candidate: Candidate, configuration: BackendConfigurationStore) throws {
    let previous = try record(Self.activeKey)
    let retired = (previous?.retiredNamespaces ?? []) + [previous?.namespace ?? Self.legacyNamespace]
    let record = Record(namespace: candidate.namespace, draft: candidate.draft, retiredNamespaces: retired.filter { $0 != candidate.namespace })
    // Configuration and session/proof namespace become authoritative together.
    // A crash before this write keeps the old setup; a crash after it replays
    // the matching preferences at startup before AuthService is constructed.
    try root.writeData(try JSONCodec.encoder.encode(record), account: Self.activeKey)
    record.draft.apply(to: configuration)
    try? root.delete(account: Self.pendingKey)
    cleanupRetired()
  }

  func updateConfiguration(_ configuration: BackendConfigurationStore) throws {
    guard let active = try record(Self.activeKey) else { return }
    let updated = Record(namespace: active.namespace, draft: BackendConnectionDraft(configuration: configuration), retiredNamespaces: active.retiredNamespaces)
    try root.writeData(try JSONCodec.encoder.encode(updated), account: Self.activeKey)
  }

  private func removeNamespace(_ namespace: UUID) throws {
    for account in Self.authAccounts {
      try root.delete(account: namespace == Self.legacyNamespace ? account : ScopedConnectionPersistence.account(account, namespace: namespace))
    }
  }

  private func cleanupRetired() {
    guard var active = try? record(Self.activeKey) else { return }
    var remaining: [UUID] = []
    for namespace in active.retiredNamespaces ?? [] where namespace != active.namespace {
      do { try removeNamespace(namespace) } catch { remaining.append(namespace) }
    }
    guard active.retiredNamespaces != remaining else { return }
    active.retiredNamespaces = remaining
    if let data = try? JSONCodec.encoder.encode(active) { try? root.writeData(data, account: Self.activeKey) }
  }

  private func routedAccount(_ account: String) throws -> String {
    guard let active = try record(Self.activeKey) else { return account }
    return ScopedConnectionPersistence.account(account, namespace: active.namespace)
  }

  func readData(account: String) throws -> Data? { try root.readData(account: routedAccount(account)) }
  func writeData(_ data: Data, account: String) throws { try root.writeData(data, account: routedAccount(account)) }
  func delete(account: String) throws { try root.delete(account: routedAccount(account)) }
}

@MainActor
private final class ScopedConnectionPersistence: BackendSessionPersistence {
  let root: any BackendSessionPersistence
  let namespace: UUID
  init(root: any BackendSessionPersistence, namespace: UUID) { self.root = root; self.namespace = namespace }
  static func account(_ account: String, namespace: UUID) -> String { "connection.\(namespace.uuidString).\(account)" }
  func readData(account: String) throws -> Data? { try root.readData(account: Self.account(account, namespace: namespace)) }
  func writeData(_ data: Data, account: String) throws { try root.writeData(data, account: Self.account(account, namespace: namespace)) }
  func delete(account: String) throws { try root.delete(account: Self.account(account, namespace: namespace)) }
}
