import Foundation

/// One owner across preparation, consuming POST, and durable commit. Invalidation
/// is synchronous and deliberately does not wait for a network owner's lease.
@MainActor
final class AuthSessionCommitter {
  private let store: BackendSessionStore?
  private var memoryState = AuthInvalidationState(generation: AuthInvalidationState.initialGeneration, invalidated: false)
  private var memoryJournal: AuthOperationJournal?
  private var blockedInProcess = false
  private var lease: UUID?
  private var leaseWaiters: [(UUID, CheckedContinuation<UUID, Never>)] = []

  init(store: BackendSessionStore?) { self.store = store }

  func acquireLease() async throws -> UUID {
    guard !blockedInProcess else { throw AuthCommitError.invalidationIncomplete }
    let id = UUID()
    if lease == nil {
      lease = id
    } else {
      _ = await withCheckedContinuation { continuation in
        leaseWaiters.append((id, continuation))
      }
    }
    if Task.isCancelled { releaseLease(id); throw CancellationError() }
    if blockedInProcess { releaseLease(id); throw AuthCommitError.invalidationIncomplete }
    return id
  }

  func releaseLease(_ id: UUID) {
    guard lease == id else { return }
    if leaseWaiters.isEmpty { lease = nil; return }
    let next = leaseWaiters.removeFirst()
    lease = next.0
    next.1.resume(returning: next.0)
  }

  private func state() throws -> AuthInvalidationState {
    if let store { return try store.loadAuthInvalidationState() }
    return memoryState
  }

  private func journal() throws -> AuthOperationJournal? {
    if let store { return try store.loadAuthJournal() }
    return memoryJournal
  }

  private func saveJournal(_ record: AuthOperationJournal) throws {
    try store?.saveAuthJournal(record)
    memoryJournal = record
  }

  private func clearJournal() throws {
    try store?.clearAuthJournal()
    memoryJournal = nil
  }

  var isBusy: Bool { lease != nil }

  func enrollmentSource(binding: AuthConnectionBinding, memory: AuthenticatedConnection?) throws -> AuthenticatedConnection? {
    guard !(try state()).invalidated else { return nil }
    return try store?.loadConnection(binding: binding) ?? memory
  }

  var hasUnresolvedSubmission: Bool {
    // Failure to inspect metadata blocks credentials as well as enrollment.
    do { return try journal().map { $0.phase != .prepared || $0.inheritedUncertainty != nil } ?? false }
    catch { return true }
  }

  func load(binding: AuthConnectionBinding, proofProvider: DeviceSessionProofProviding) throws -> AuthenticatedConnection? {
    guard !blockedInProcess else { throw AuthCommitError.invalidationIncomplete }
    guard lease == nil else { throw AuthCommitError.commitPending }
    let currentState = try state()
    if let record = try journal() {
      if record.generation != currentState.generation || record.binding != binding {
        // A durably stored configuration is authoritative on restart. The
        // mismatched operation can never commit into this selected connection.
        try clearJournal()
      } else {
        switch record.phase {
        case .prepared:
          if let inherited = record.inheritedUncertainty {
            guard inherited == record.capturedSource else { throw AuthCommitError.operationReplaced }
            throw AuthCommitError.uncertainSubmission
          }
          try clearJournal() // No POST was permitted for this record.
        case .submitted:
          throw AuthCommitError.uncertainSubmission
        case .responseReceived:
          return try replay(record, binding: binding, proofProvider: proofProvider)
        }
      }
    }
    guard !currentState.invalidated else { return nil }
    return try store?.loadConnection(binding: binding)
  }

  func begin(kind: AuthOperationJournal.Kind, binding: AuthConnectionBinding,
             source: AuthenticatedConnection?, proofRequestID: String, proofKeyID: String?) throws -> UUID {
    guard !blockedInProcess else { throw AuthCommitError.invalidationIncomplete }
    let currentState = try state()
    if let source, source.identity.binding != binding { throw AuthCommitError.operationReplaced }
    let fingerprint = try AuthOperationJournal.fingerprint(source)
    var inherited: AuthOperationJournal.SourceUncertainty?
    if let old = try journal(), old.generation == currentState.generation, old.binding == binding {
      if old.phase == .responseReceived { throw AuthCommitError.commitPending }
      if old.phase == .submitted || old.inheritedUncertainty != nil {
        if kind == .refresh { throw AuthCommitError.uncertainSubmission }
        inherited = old.inheritedUncertainty ?? old.capturedSource
        let expected = AuthOperationJournal.SourceUncertainty(generation: currentState.generation,
          binding: binding, identity: source?.identity, fingerprint: fingerprint)
        guard inherited == expected, inherited == old.capturedSource else { throw AuthCommitError.operationReplaced }
      }
    }
    if kind == .refresh, currentState.invalidated { throw AuthCommitError.operationReplaced }
    let id = UUID()
    var record = AuthOperationJournal(operationID: id, kind: kind, generation: currentState.generation,
      binding: binding, sourceIdentity: source?.identity, sourceFingerprint: fingerprint,
      proofRequestID: proofRequestID, proofKeyID: proofKeyID, phase: .prepared, target: nil)
    record.inheritedUncertainty = inherited
    try saveJournal(record)
    return id
  }

  private func owned(_ id: UUID, binding: AuthConnectionBinding) throws -> AuthOperationJournal {
    guard !blockedInProcess, let record = try journal(), record.operationID == id,
          record.binding == binding, record.generation == (try state()).generation else {
      throw AuthCommitError.operationReplaced
    }
    return record
  }

  func submitted(_ id: UUID, binding: AuthConnectionBinding, source: AuthenticatedConnection?) throws {
    var record = try owned(id, binding: binding)
    guard record.phase == .prepared, record.sourceIdentity == source?.identity,
          record.sourceFingerprint == (try AuthOperationJournal.fingerprint(source)) else {
      throw AuthCommitError.operationReplaced
    }
    if let store, !(try state()).invalidated {
      let persisted = try store.loadConnection(binding: binding)
      guard record.sourceFingerprint == (try AuthOperationJournal.fingerprint(persisted)) else {
        throw AuthCommitError.operationReplaced
      }
    }
    record.phase = .submitted
    try saveJournal(record) // Must succeed immediately before a consuming POST.
  }

  func validateSubmitted(_ id: UUID, binding: AuthConnectionBinding) throws {
    guard try owned(id, binding: binding).phase == .submitted else { throw AuthCommitError.operationReplaced }
  }

  func rejectDefinitively(_ id: UUID, binding: AuthConnectionBinding) throws {
    var record = try owned(id, binding: binding)
    guard record.phase == .submitted else { return }
    if let inherited = record.inheritedUncertainty {
      guard inherited == record.capturedSource else { throw AuthCommitError.operationReplaced }
      record.phase = .prepared // This request was rejected; its ancestor remains uncertain.
      try saveJournal(record)
    } else {
      try clearJournal()
    }
  }

  func receive(_ response: BackendSessionResponse, operationID: UUID, binding: AuthConnectionBinding,
               proofProvider: DeviceSessionProofProviding) throws -> AuthenticatedConnection {
    var record = try owned(operationID, binding: binding)
    guard record.phase == .submitted, response.protocolVersion == 3,
          response.serviceMode == binding.mode.rawValue else { throw AuthCommitError.operationReplaced }
    let source = DataSourceMode(rawValue: response.dataSourceMode) ?? .unknown
    guard source != .unknown else { throw HealthImportError.unverifiedSource }
    if binding.purpose == .liveImport, source == .syntheticDemo { throw HealthImportError.previewOnly }
    let identity = record.kind == .refresh ? record.sourceIdentity : AuthConnectionIdentity(id: UUID(), binding: binding)
    guard let identity else { throw AuthCommitError.operationReplaced }
    record.target = StoredAuthConnection(session: response, identity: identity)
    record.phase = .responseReceived
    record.finalProofState = record.kind == .enrollment && record.proofKeyID != nil ? .registered : .unchanged
    try saveJournal(record) // Retain confirmed response before either final write.
    return try replay(record, binding: binding, proofProvider: proofProvider)
  }

  private func replay(_ record: AuthOperationJournal, binding: AuthConnectionBinding,
                      proofProvider: DeviceSessionProofProviding) throws -> AuthenticatedConnection {
    _ = try owned(record.operationID, binding: binding)
    let intendedProofState: AuthOperationJournal.FinalProofState = record.kind == .enrollment && record.proofKeyID != nil ? .registered : .unchanged
    guard record.phase == .responseReceived, record.finalProofState == intendedProofState else {
      throw AuthCommitError.operationReplaced
    }
    guard let storedTarget = record.target, let identity = storedTarget.identity, identity.binding == binding else {
      throw AuthCommitError.operationReplaced
    }
    let target = AuthenticatedConnection(session: storedTarget.session, identity: identity)
    guard target.session.protocolVersion == 3, target.session.serviceMode == binding.mode.rawValue else {
      throw AuthCommitError.operationReplaced
    }
    let sourceMode = DataSourceMode(rawValue: target.session.dataSourceMode) ?? .unknown
    guard sourceMode != .unknown else { throw HealthImportError.unverifiedSource }
    if binding.purpose == .liveImport, sourceMode == .syntheticDemo { throw HealthImportError.previewOnly }
    if record.kind == .refresh {
      guard identity == record.sourceIdentity else { throw AuthCommitError.operationReplaced }
      if let keyID = record.proofKeyID, !(try proofProvider.hostedRegisteredKeyMatches(keyID)) {
        throw AuthCommitError.proofStateReplaced
      }
    }
    if let store {
      let persisted = try store.loadConnection(binding: binding)
      let persistedFingerprint = try AuthOperationJournal.fingerprint(persisted)
      let targetFingerprint = try AuthOperationJournal.fingerprint(target)
      let isExactTarget = persisted?.identity == target.identity && persistedFingerprint == targetFingerprint
      let current = (try state()).invalidated && !isExactTarget ? nil : persisted
      let fingerprint = try AuthOperationJournal.fingerprint(current)
      guard isExactTarget || (current?.identity == record.sourceIdentity && fingerprint == record.sourceFingerprint) else {
        throw AuthCommitError.operationReplaced
      }
      if !isExactTarget { try store.save(target) }
    }
    if record.kind == .enrollment, let keyID = record.proofKeyID {
      guard try proofProvider.markHostedEnrollmentRegistered(keyId: keyID, requestId: record.proofRequestID) else {
        throw AuthCommitError.proofStateReplaced
      }
    }
    let active = AuthInvalidationState(generation: record.generation, invalidated: false)
    try store?.saveAuthInvalidationState(active)
    memoryState = active
    try clearJournal() // Publication is allowed only after every durable write.
    return target
  }

  /// A direct local installation still crosses the same durable mutation owner.
  /// Used by isolated preview/setup consumers; network paths use receive/replay.
  func install(_ connection: AuthenticatedConnection) throws {
    guard lease == nil, !blockedInProcess, !(try hasPendingJournal()) else { throw AuthCommitError.commitPending }
    try store?.save(connection)
    let active = AuthInvalidationState(generation: try state().generation, invalidated: false)
    try store?.saveAuthInvalidationState(active)
    memoryState = active
  }

  private func hasPendingJournal() throws -> Bool { try journal() != nil }

  /// A protected request may invalidate only the exact credentials it sent.
  /// A pending auth operation owns recovery; a late rejection cannot erase it.
  func invalidateIfCurrent(_ expected: AuthenticatedConnection, binding: AuthConnectionBinding) throws -> Bool {
    do {
      guard expected.identity.binding == binding, !(try state()).invalidated,
            try journal() == nil else { return false }
      if let store {
        let persisted = try store.loadConnection(binding: binding)
        guard persisted?.identity == expected.identity,
              try AuthOperationJournal.fingerprint(persisted) == AuthOperationJournal.fingerprint(expected) else {
          return false
        }
      }
      try invalidate()
      return true
    } catch {
      blockedInProcess = true
      if let activeLease = lease { releaseLease(activeLease) }
      throw AuthCommitError.invalidationIncomplete
    }
  }

  func invalidate() throws {
    blockedInProcess = true
    // A superseded network owner may finish later, but cannot mutate this
    // generation. Its old release token cannot release a replacement lease.
    if let activeLease = lease { releaseLease(activeLease) }
    let tombstone = AuthInvalidationState(generation: UUID(), invalidated: true)
    memoryState = tombstone
    do {
      try store?.saveAuthInvalidationState(tombstone)
    } catch {
      // Independent device-only tombstone handles failure of the primary write.
      do { try store?.saveAuthInvalidationFallback(tombstone) }
      catch { throw AuthCommitError.invalidationIncomplete }
    }
    blockedInProcess = false
    // Cleanup is not required for safety: the generation rejects old callbacks.
    try? store?.delete()
    try? clearJournal()
  }
}
