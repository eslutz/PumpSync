import CryptoKit
import DeviceCheck
import Foundation

@MainActor
protocol AppAttestClient: AnyObject {
  var isSupported: Bool { get }
  func generateKey() async throws -> String
  func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
  func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

@MainActor
final class LiveAppAttestClient: AppAttestClient {
  private let service: DCAppAttestService

  init(service: DCAppAttestService = .shared) {
    self.service = service
  }

  var isSupported: Bool { service.isSupported }

  func generateKey() async throws -> String {
    do { return try await service.generateKey() } catch { throw Self.map(error) }
  }

  func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
    do { return try await service.attestKey(keyId, clientDataHash: clientDataHash) } catch { throw Self.map(error) }
  }

  func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
    do { return try await service.generateAssertion(keyId, clientDataHash: clientDataHash) } catch { throw Self.map(error) }
  }

  private static func map(_ error: Error) -> Error {
    let nsError = error as NSError
    guard nsError.domain == DCError.errorDomain else { return error }
    switch DCError.Code(rawValue: nsError.code) {
    case .serverUnavailable:
      return AppAttestClientError.serverUnavailable
    case .invalidKey:
      return AppAttestClientError.invalidKey
    default:
      return AppAttestClientError.nonRetryable
    }
  }
}

enum AppAttestClientError: Error {
  case serverUnavailable
  case invalidKey
  case nonRetryable
}

@MainActor
protocol DeviceSessionProofProviding {
  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition
  func invalidateHostedProofOperation()

  func hostedEnrollment(
    challenge: SessionChallengeResponse,
    installationId: String,
    signedTransactionInfo: String
  ) async throws -> HostedDeviceEnrollment
  func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool
  func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool
  func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool
  func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool
  func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool
  func discardRegisteredHostedKey() throws -> Bool
  func releaseHostedProofOperation(requestId: String) -> Bool

  func selfHostedEnrollment(
    challenge: SessionChallengeResponse,
    installationId: String
  ) throws -> SelfHostedDeviceEnrollment

  func hostedProofKeyID(requestId: String) throws -> String
  func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool

  func refreshRequest(
    session: BackendSessionResponse,
    installationId: String,
    mode: BackendAccessMode
  ) async throws -> SessionRefreshRequest
}

private enum AppAttestKeyPhase: String, Codable {
  case attesting
  case attestationPrepared
  case reconciliationPrepared
  case registrationUnknown
  case registered
  case registeredAssertionPrepared
  case registeredAssertionSubmitted
}

private struct PendingHostedEnrollment: Codable, Equatable {
  let enrollment: HostedDeviceEnrollment
  let challengeExpiresAt: Date
  let transactionHash: String
}

private struct PersistedAppAttestKeyState: Codable, Equatable {
  let keyId: String
  var phase: AppAttestKeyPhase
  var pendingEnrollment: PendingHostedEnrollment?
  var registeredRequestId: String? = nil
  // Nil retains conservative interpretation of legacy reconciliation records.
  var requiresSubmissionReconciliation: Bool? = nil
}

enum HostedProofRecoveryDisposition: Equatable {
  case ready
  case enrollmentRequired
  case reconciliationRequired(keyID: String, requestID: String?)
}

private struct HostedProofOperation {
  let id = UUID()
  let requestId: String
}

@MainActor
final class DeviceSessionProofProvider: DeviceSessionProofProviding {
  private static let secureEnclaveKeyAccount = "device-proof.secure-enclave-p256.v1"
  private static let appAttestStateAccount = "device-proof.app-attest-state.v4"

  private let keychain: any BackendSessionPersistence
  private let now: () -> Date
  private let appAttest: AppAttestClient
  private let diagnostics: DiagnosticsLogStore?
  private let appAttestAssertionTimeout: Duration
  private var hostedProofOperation: HostedProofOperation?
  private var cancelAppleOperation: (id: UUID, cancel: () -> Void)?

  init(
    keychain: any BackendSessionPersistence,
    now: @escaping () -> Date = Date.init,
    appAttest: AppAttestClient = LiveAppAttestClient(),
    diagnostics: DiagnosticsLogStore? = nil,
    appAttestAssertionTimeout: Duration = .seconds(8)
  ) {
    self.keychain = keychain
    self.now = now
    self.appAttest = appAttest
    self.diagnostics = diagnostics
    self.appAttestAssertionTimeout = appAttestAssertionTimeout
  }

  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition {
    guard let state = try loadState() else { return .enrollmentRequired }
    switch state.phase {
    case .registered: return .ready
    case .registrationUnknown, .registeredAssertionSubmitted:
      return .reconciliationRequired(keyID: state.keyId, requestID: state.pendingEnrollment?.enrollment.requestId)
    case .reconciliationPrepared:
      return state.requiresSubmissionReconciliation == false ? .enrollmentRequired
        : .reconciliationRequired(keyID: state.keyId, requestID: state.pendingEnrollment?.enrollment.requestId)
    case .registeredAssertionPrepared:
      return state.requiresSubmissionReconciliation == true
        ? .reconciliationRequired(keyID: state.keyId, requestID: state.pendingEnrollment?.enrollment.requestId) : .enrollmentRequired
    case .attesting, .attestationPrepared:
      return .enrollmentRequired
    }
  }

  func hostedEnrollment(
    challenge: SessionChallengeResponse,
    installationId: String,
    signedTransactionInfo: String
  ) async throws -> HostedDeviceEnrollment {
    guard appAttest.isSupported else { throw DeviceSessionProofError.appAttestUnavailable }
    let state = try loadState()
    let transactionHash = Self.base64URL(Data(SHA256.hash(data: Data(signedTransactionInfo.utf8))))
    let reusableRequestId: String?
    if let state,
       state.phase == .registeredAssertionPrepared
         || state.phase == .reconciliationPrepared
         || state.phase == .attestationPrepared,
       let pending = state.pendingEnrollment,
       pending.transactionHash == transactionHash,
       pending.enrollment.challengeToken == challenge.challengeToken,
       pending.challengeExpiresAt > now() {
      reusableRequestId = pending.enrollment.requestId
    } else {
      reusableRequestId = nil
    }
    let requestId = reusableRequestId ?? UUID().uuidString
    return try await withHostedProofOperation(requestId: requestId) {
      return try await prepareHostedEnrollment(
        state: state,
        challenge: challenge,
        installationId: installationId,
        signedTransactionInfo: signedTransactionInfo,
        transactionHash: transactionHash,
        requestId: requestId
      )
    }
  }

  private func prepareHostedEnrollment(
    state initialState: PersistedAppAttestKeyState?,
    challenge: SessionChallengeResponse,
    installationId: String,
    signedTransactionInfo: String,
    transactionHash: String,
    requestId: String
  ) async throws -> HostedDeviceEnrollment {
    let state = initialState
    if let state, state.phase == .registeredAssertionPrepared,
       let pending = state.pendingEnrollment,
       pending.transactionHash == transactionHash,
       pending.enrollment.challengeToken == challenge.challengeToken,
       pending.challengeExpiresAt > now() {
      var enrollment = pending.enrollment
      enrollment.preparation = .reused
      return enrollment
    }
    if let state,
       state.phase == .registered
         || state.phase == .registeredAssertionPrepared
         || state.phase == .registeredAssertionSubmitted {
      return try await registeredAssertionEnrollment(
        keyId: state.keyId,
        challenge: challenge,
        installationId: installationId,
        signedTransactionInfo: signedTransactionInfo,
        transactionHash: transactionHash,
        requestId: requestId,
        preparation: .generated,
        wasSubmitted: state.phase == .registeredAssertionSubmitted || state.requiresSubmissionReconciliation == true
      )
    }

    if let state, state.phase == .registrationUnknown {
      return try await reconciliationEnrollment(
        keyId: state.keyId,
        challenge: challenge,
        installationId: installationId,
        signedTransactionInfo: signedTransactionInfo,
        transactionHash: transactionHash,
        requestId: requestId
      )
    }
    if let state, state.phase == .reconciliationPrepared,
       let pending = state.pendingEnrollment,
       pending.transactionHash == transactionHash,
       pending.enrollment.challengeToken == challenge.challengeToken,
       pending.challengeExpiresAt > now() {
      var enrollment = pending.enrollment
      enrollment.preparation = .reconciliation
      return enrollment
    }
    if let state, state.phase == .reconciliationPrepared {
      return try await reconciliationEnrollment(
        keyId: state.keyId,
        challenge: challenge,
        installationId: installationId,
        signedTransactionInfo: signedTransactionInfo,
        transactionHash: transactionHash,
        requestId: requestId,
        wasSubmitted: state.requiresSubmissionReconciliation ?? true
      )
    }
    if let state, state.phase == .attestationPrepared,
       let pending = state.pendingEnrollment,
       pending.transactionHash == transactionHash,
       pending.enrollment.challengeToken == challenge.challengeToken,
       pending.challengeExpiresAt > now() {
      var enrollment = pending.enrollment
      enrollment.preparation = .reused
      return enrollment
    }
    if let state, state.phase == .attestationPrepared {
      return try await reconciliationEnrollment(
        keyId: state.keyId, challenge: challenge, installationId: installationId,
        signedTransactionInfo: signedTransactionInfo, transactionHash: transactionHash, requestId: requestId, wasSubmitted: false
      )
    }

    let keyId: String
    if let state, state.phase == .attesting {
      keyId = state.keyId
    } else {
      keyId = try await performAppleOperation { try await self.appAttest.generateKey() }
      try saveState(PersistedAppAttestKeyState(keyId: keyId, phase: .attesting, pendingEnrollment: nil))
    }

    let issuedAt = now()
    let payload = DeviceProofPayload.hostedEnrollment(
      installationId: installationId,
      requestId: requestId,
      issuedAt: issuedAt,
      challengeToken: challenge.challengeToken,
      keyId: keyId,
      signedTransactionInfo: signedTransactionInfo
    )
    let attestation: Data
    do {
      attestation = try await performAppleOperation { try await self.appAttest.attestKey(keyId, clientDataHash: payload.hash) }
    } catch AppAttestClientError.serverUnavailable {
      throw AppAttestClientError.serverUnavailable
    } catch AppAttestClientError.invalidKey {
      try clearState()
      throw AppAttestClientError.invalidKey
    }

    let enrollment = HostedDeviceEnrollment(
      requestId: requestId,
      issuedAt: issuedAt,
      challengeToken: challenge.challengeToken,
      keyId: keyId,
      proofKind: "attestation",
      proof: attestation.base64EncodedString(),
      clientDataFingerprint: Self.clientDataFingerprint(payload.encoded)
    )
    try saveState(PersistedAppAttestKeyState(
      keyId: keyId,
      phase: .attestationPrepared,
      pendingEnrollment: PendingHostedEnrollment(
        enrollment: enrollment,
        challengeExpiresAt: challenge.expiresAt,
        transactionHash: transactionHash
      )
    ))
    return enrollment
  }

  func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool {
    guard var state = try loadState(), state.keyId == keyId else { return false }
    if (state.phase == .registrationUnknown || state.phase == .registeredAssertionSubmitted),
       state.pendingEnrollment?.enrollment.requestId == requestId {
      return true
    }
    guard state.phase == .attestationPrepared
            || state.phase == .reconciliationPrepared
            || state.phase == .registeredAssertionPrepared,
          state.pendingEnrollment?.enrollment.requestId == requestId else {
      return false
    }
    state.phase = state.phase == .registeredAssertionPrepared
      ? .registeredAssertionSubmitted
      : .registrationUnknown
    state.requiresSubmissionReconciliation = true
    try saveState(state)
    return true
  }

  func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool {
    guard let state = try loadState(), state.keyId == keyId else { return false }
    if state.phase == .registered { return state.registeredRequestId == requestId }
    guard (state.phase == .registrationUnknown || state.phase == .registeredAssertionSubmitted),
          state.pendingEnrollment?.enrollment.requestId == requestId else {
      return false
    }
    try saveState(PersistedAppAttestKeyState(keyId: keyId, phase: .registered, pendingEnrollment: nil, registeredRequestId: requestId))
    return true
  }

  func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool {
    guard var state = try loadState(),
          state.keyId == keyId,
          state.phase == .registrationUnknown || state.phase == .registeredAssertionSubmitted,
          let pendingEnrollment = state.pendingEnrollment,
          pendingEnrollment.enrollment.requestId == requestId else {
      return false
    }
    defer { _ = releaseHostedProofOperation(requestId: requestId) }
    if pendingEnrollment.enrollment.proofKind == "assertion" {
      state.phase = .registered
      state.pendingEnrollment = nil
      try saveState(state)
    } else {
      state.phase = .attestationPrepared
      state.pendingEnrollment = nil
      try saveState(state)
    }
    return true
  }

  func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool {
    guard var state = try loadState(),
          state.keyId == keyId,
          let pendingEnrollment = state.pendingEnrollment,
          pendingEnrollment.enrollment.requestId == requestId else {
      return false
    }
    switch state.phase {
    case .attestationPrepared:
      defer { _ = releaseHostedProofOperation(requestId: requestId) }
      state.pendingEnrollment = nil
      try saveState(state)
      return true
    case .reconciliationPrepared:
      defer { _ = releaseHostedProofOperation(requestId: requestId) }
      state.phase = state.requiresSubmissionReconciliation == false ? .attestationPrepared : .registrationUnknown
      state.pendingEnrollment = nil
      try saveState(state)
      return true
    case .registeredAssertionPrepared:
      defer { _ = releaseHostedProofOperation(requestId: requestId) }
      state.phase = state.requiresSubmissionReconciliation == true ? .registeredAssertionSubmitted : .registered
      state.pendingEnrollment = nil
      try saveState(state)
      return true
    case .attesting, .registrationUnknown, .registered, .registeredAssertionSubmitted:
      return false
    }
  }

  func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool {
    guard let state = try loadState(),
          state.keyId == keyId,
          state.phase == .registrationUnknown || state.phase == .registeredAssertionSubmitted,
          let pendingEnrollment = state.pendingEnrollment,
          pendingEnrollment.enrollment.requestId == requestId else {
      return false
    }
    defer { _ = releaseHostedProofOperation(requestId: requestId) }
    try clearState()
    return true
  }

  func discardRegisteredHostedKey() throws -> Bool {
    guard let state = try loadState(), state.phase == .registered else { return false }
    try clearState()
    return true
  }

  private func assertionEnrollment(
    keyId: String,
    challenge: SessionChallengeResponse,
    installationId: String,
    signedTransactionInfo: String,
    requestId: String,
    preparation: HostedDeviceProofPreparation
  ) async throws -> HostedDeviceEnrollment {
    let issuedAt = now()
    let payload = DeviceProofPayload.hostedEnrollment(
      installationId: installationId,
      requestId: requestId,
      issuedAt: issuedAt,
      challengeToken: challenge.challengeToken,
      keyId: keyId,
      signedTransactionInfo: signedTransactionInfo
    )
    let assertion: Data
    do {
      assertion = try await performAppleOperation { try await self.appAttest.generateAssertion(keyId, clientDataHash: payload.hash) }
    } catch AppAttestClientError.invalidKey {
      try clearState()
      throw AppAttestClientError.invalidKey
    }
    return HostedDeviceEnrollment(
      requestId: requestId,
      issuedAt: issuedAt,
      challengeToken: challenge.challengeToken,
      keyId: keyId,
      proofKind: "assertion",
      proof: assertion.base64EncodedString(),
      preparation: preparation,
      clientDataFingerprint: Self.clientDataFingerprint(payload.encoded)
    )
  }

  private func reconciliationEnrollment(
    keyId: String,
    challenge: SessionChallengeResponse,
    installationId: String,
    signedTransactionInfo: String,
    transactionHash: String,
    requestId: String,
    wasSubmitted: Bool = true
  ) async throws -> HostedDeviceEnrollment {
    let enrollment = try await assertionEnrollment(
      keyId: keyId,
      challenge: challenge,
      installationId: installationId,
      signedTransactionInfo: signedTransactionInfo,
      requestId: requestId,
      preparation: .reconciliation
    )
    try saveState(PersistedAppAttestKeyState(
      keyId: keyId,
      phase: .reconciliationPrepared,
      pendingEnrollment: PendingHostedEnrollment(
        enrollment: enrollment,
        challengeExpiresAt: challenge.expiresAt,
        transactionHash: transactionHash
      ),
      requiresSubmissionReconciliation: wasSubmitted
    ))
    return enrollment
  }

  private func registeredAssertionEnrollment(
    keyId: String,
    challenge: SessionChallengeResponse,
    installationId: String,
    signedTransactionInfo: String,
    transactionHash: String,
    requestId: String,
    preparation: HostedDeviceProofPreparation,
    wasSubmitted: Bool = false
  ) async throws -> HostedDeviceEnrollment {
    let enrollment = try await assertionEnrollment(
      keyId: keyId,
      challenge: challenge,
      installationId: installationId,
      signedTransactionInfo: signedTransactionInfo,
      requestId: requestId,
      preparation: preparation
    )
    try saveState(PersistedAppAttestKeyState(
      keyId: keyId,
      phase: .registeredAssertionPrepared,
      pendingEnrollment: PendingHostedEnrollment(
        enrollment: enrollment,
        challengeExpiresAt: challenge.expiresAt,
        transactionHash: transactionHash
      ),
      requiresSubmissionReconciliation: wasSubmitted
    ))
    return enrollment
  }

  func invalidateHostedProofOperation() {
    guard let owner = hostedProofOperation else { return }
    hostedProofOperation = nil
    if cancelAppleOperation?.id == owner.id {
      let cancel = cancelAppleOperation?.cancel
      cancelAppleOperation = nil
      cancel?()
    }
  }

  func releaseHostedProofOperation(requestId: String) -> Bool {
    guard hostedProofOperation?.requestId == requestId else { return false }
    hostedProofOperation = nil
    return true
  }

  private func withHostedProofOperation<T>(
    requestId: String,
    operation: () async throws -> T
  ) async throws -> T {
    guard hostedProofOperation == nil else {
      throw DeviceSessionProofError.hostedProofOperationInProgress
    }
    try Task.checkCancellation()
    let owner = HostedProofOperation(requestId: requestId)
    hostedProofOperation = owner
    do {
      let result = try await operation()
      try Task.checkCancellation()
      guard hostedProofOperation?.id == owner.id else { throw CancellationError() }
      return result
    } catch {
      if hostedProofOperation?.id == owner.id { hostedProofOperation = nil }
      throw error
    }
  }

  func selfHostedEnrollment(challenge: SessionChallengeResponse, installationId: String) throws -> SelfHostedDeviceEnrollment {
    let key = try secureEnclaveKey()
    let issuedAt = now()
    let requestId = UUID().uuidString
    let payload = DeviceProofPayload.selfHostedEnrollment(
      installationId: installationId,
      requestId: requestId,
      issuedAt: issuedAt,
      challengeToken: challenge.challengeToken
    )
    let signature = try key.signature(for: payload.encoded)
    return SelfHostedDeviceEnrollment(
      requestId: requestId,
      issuedAt: issuedAt,
      challengeToken: challenge.challengeToken,
      publicKey: Self.subjectPublicKeyInfo(key.publicKey.x963Representation).base64EncodedString(),
      signature: signature.derRepresentation.base64EncodedString()
    )
  }

  func hostedProofKeyID(requestId: String) throws -> String {
    guard hostedProofOperation?.requestId == requestId,
          let state = try loadState(), state.phase == .registered else {
      throw DeviceSessionProofError.hostedProofOperationInProgress
    }
    return state.keyId
  }

  func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool {
    guard let state = try loadState() else { return false }
    return state.phase == .registered && state.keyId == keyId
  }

  func refreshRequest(session: BackendSessionResponse, installationId: String, mode: BackendAccessMode) async throws -> SessionRefreshRequest {
    guard !session.refreshToken.isEmpty else { throw DeviceSessionProofError.missingRenewableCredential }
    let requestId = UUID().uuidString
    let issuedAt = now()
    let proof: Data
    switch mode {
    case .hosted:
      proof = try await withHostedProofOperation(requestId: requestId) {
        guard appAttest.isSupported else {
          throw DeviceSessionProofError.appAttestUnavailable
        }
        let stateReadStartedAt = Date()
        diagnostics?.record(
          source: .auth,
          title: "Hosted proof state read started",
          message: "operation=sessionRefresh"
        )
        let persistedState: PersistedAppAttestKeyState?
        do {
          persistedState = try loadState()
        } catch {
          diagnostics?.record(
            source: .auth,
            severity: .warning,
            title: "Hosted proof state read failed",
            message: "operation=sessionRefresh reason=keychainAccess elapsedMs=\(elapsedMilliseconds(since: stateReadStartedAt))"
          )
          throw error
        }
        guard let state = persistedState else {
          diagnostics?.record(
            source: .auth,
            severity: .warning,
            title: "Hosted proof state read completed",
            message: "operation=sessionRefresh outcome=missing elapsedMs=\(elapsedMilliseconds(since: stateReadStartedAt))"
          )
          throw DeviceSessionProofError.appAttestUnavailable
        }
        diagnostics?.record(
          source: .auth,
          title: "Hosted proof state read completed",
          message: "operation=sessionRefresh outcome=\(state.phase.rawValue) elapsedMs=\(elapsedMilliseconds(since: stateReadStartedAt))"
        )
        switch state.phase {
        case .registered:
          break
        case .attesting, .attestationPrepared, .reconciliationPrepared, .registrationUnknown,
             .registeredAssertionPrepared, .registeredAssertionSubmitted:
          throw DeviceSessionProofError.appAttestUnavailable
        }
        let payload = DeviceProofPayload.refresh(
          installationId: installationId,
          requestId: requestId,
          issuedAt: issuedAt,
          refreshToken: session.refreshToken,
          keyId: state.keyId
        )
        let assertionStartedAt = Date()
        diagnostics?.record(
          source: .auth,
          title: "App Attest assertion generation started",
          message: "operation=sessionRefresh"
        )
        do {
          let assertion = try await generateAssertionWithTimeout(
            keyId: state.keyId,
            clientDataHash: payload.hash
          )
          diagnostics?.record(
            source: .auth,
            title: "App Attest assertion generation completed",
            message: "operation=sessionRefresh outcome=success elapsedMs=\(elapsedMilliseconds(since: assertionStartedAt))"
          )
          return assertion
        } catch AppAttestClientError.invalidKey {
          diagnostics?.record(
            source: .auth,
            severity: .warning,
            title: "App Attest assertion generation failed",
            message: "operation=sessionRefresh reason=invalidKey elapsedMs=\(elapsedMilliseconds(since: assertionStartedAt))"
          )
          try clearState()
          throw AppAttestClientError.invalidKey
        } catch {
          diagnostics?.record(
            source: .auth,
            severity: .warning,
            title: "App Attest assertion generation failed",
            message: "operation=sessionRefresh reason=\(Self.assertionFailureReason(error)) elapsedMs=\(elapsedMilliseconds(since: assertionStartedAt))"
          )
          throw error
        }
      }
    case .selfHosted:
      let payload = DeviceProofPayload.refresh(
        installationId: installationId,
        requestId: requestId,
        issuedAt: issuedAt,
        refreshToken: session.refreshToken,
        keyId: ""
      )
      proof = try secureEnclaveKey().signature(for: payload.encoded).derRepresentation
    }
    return SessionRefreshRequest(
      installationId: installationId,
      refreshToken: session.refreshToken,
      requestId: requestId,
      issuedAt: issuedAt,
      proof: proof.base64EncodedString()
    )
  }

  private func loadState() throws -> PersistedAppAttestKeyState? {
    guard let data = try keychain.readData(account: Self.appAttestStateAccount) else { return nil }
    return try JSONCodec.decoder.decode(PersistedAppAttestKeyState.self, from: data)
  }

  private func saveState(_ state: PersistedAppAttestKeyState) throws {
    try keychain.writeData(try JSONCodec.encoder.encode(state), account: Self.appAttestStateAccount)
  }

  private func clearState() throws {
    try keychain.delete(account: Self.appAttestStateAccount)
  }

  private func elapsedMilliseconds(since startedAt: Date) -> Int {
    Int(Date().timeIntervalSince(startedAt) * 1_000)
  }

  private func generateAssertionWithTimeout(
    keyId: String,
    clientDataHash: Data
  ) async throws -> Data {
    try await performAppleOperation { try await self.appAttest.generateAssertion(keyId, clientDataHash: clientDataHash) }
  }

  /// Race cancellation and timeout against Apple callbacks without allowing a
  /// callback from a released owner to publish proof or mutate persisted state.
  private func performAppleOperation<T: Sendable>(
    _ operation: @escaping @MainActor () async throws -> T
  ) async throws -> T {
    try Task.checkCancellation()
    guard let owner = hostedProofOperation else { throw CancellationError() }
    let race = HostedAppleOperationRace<T>()
    cancelAppleOperation = (owner.id, { race.finish(.failure(CancellationError())) })
    defer {
      if cancelAppleOperation?.id == owner.id { cancelAppleOperation = nil }
    }
    let result = try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        race.continuation = continuation
        if Task.isCancelled { race.finish(.failure(CancellationError())); return }
        race.appleTask = Task { @MainActor in
          do {
            let result = try await operation()
            guard self.hostedProofOperation?.id == owner.id else {
              race.finish(.failure(CancellationError()))
              return
            }
            race.finish(.success(result))
          } catch { race.finish(.failure(error)) }
        }
        race.timeoutTask = Task { @MainActor in
          do { try await Task.sleep(for: self.appAttestAssertionTimeout) }
          catch { return }
          race.finish(.failure(DeviceSessionProofError.appAttestTimedOut))
        }
      }
    }, onCancel: {
      Task { @MainActor in race.finish(.failure(CancellationError())) }
    })
    try Task.checkCancellation()
    guard hostedProofOperation?.id == owner.id else { throw CancellationError() }
    return result
  }

  private static func assertionFailureReason(_ error: Error) -> String {
    if Task.isCancelled || error is CancellationError {
      return "cancelled"
    }
    if case .appAttestTimedOut? = error as? DeviceSessionProofError {
      return "timeout"
    }
    switch error as? AppAttestClientError {
    case .serverUnavailable:
      return "serviceUnavailable"
    case .invalidKey:
      return "invalidKey"
    case .nonRetryable:
      return "rejected"
    case nil:
      return "unavailable"
    }
  }

  private func secureEnclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
    guard SecureEnclave.isAvailable else { throw DeviceSessionProofError.secureEnclaveUnavailable }
    if let stored = try keychain.readData(account: Self.secureEnclaveKeyAccount) {
      do { return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored) }
      catch { try? keychain.delete(account: Self.secureEnclaveKeyAccount) }
    }
    let key = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false)
    try keychain.writeData(key.dataRepresentation, account: Self.secureEnclaveKeyAccount)
    return key
  }

  private static func subjectPublicKeyInfo(_ x963: Data) -> Data {
    let prefix: [UInt8] = [
      0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
      0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    ]
    return Data(prefix) + x963
  }

  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private static func clientDataFingerprint(_ clientData: Data) -> String {
    String(base64URL(Data(SHA256.hash(data: clientData))).prefix(16))
  }
}

@MainActor
private final class HostedAppleOperationRace<T: Sendable> {
  var continuation: CheckedContinuation<T, Error>?
  var appleTask: Task<Void, Never>?
  var timeoutTask: Task<Void, Never>?

  func finish(_ result: Result<T, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    appleTask?.cancel()
    timeoutTask?.cancel()
    appleTask = nil
    timeoutTask = nil
    continuation.resume(with: result)
  }
}

struct DeviceProofPayload: Equatable {
  let encoded: Data
  var hash: Data { Data(SHA256.hash(data: encoded)) }

  static func hostedEnrollment(installationId: String, requestId: String, issuedAt: Date, challengeToken: String, keyId: String, signedTransactionInfo: String) -> Self {
    make(operation: "enroll", path: "/api/v1/subscription/session", installationId: installationId, requestId: requestId, issuedAt: issuedAt, credential: challengeToken, keyId: keyId, signedTransactionInfo: signedTransactionInfo)
  }

  static func selfHostedEnrollment(installationId: String, requestId: String, issuedAt: Date, challengeToken: String) -> Self {
    make(operation: "enroll", path: "/api/v1/self-host/session", installationId: installationId, requestId: requestId, issuedAt: issuedAt, credential: challengeToken, keyId: "", signedTransactionInfo: nil)
  }

  static func refresh(installationId: String, requestId: String, issuedAt: Date, refreshToken: String, keyId: String) -> Self {
    make(operation: "refresh", path: "/api/v1/session/refresh", installationId: installationId, requestId: requestId, issuedAt: issuedAt, credential: refreshToken, keyId: keyId, signedTransactionInfo: nil)
  }

  private static func make(operation: String, path: String, installationId: String, requestId: String, issuedAt: Date, credential: String, keyId: String, signedTransactionInfo: String?) -> Self {
    var value = Data()
    append(Data("PumpSync.DeviceSession.v3".utf8), to: &value)
    append(Data(operation.utf8), to: &value)
    append(Data(path.utf8), to: &value)
    append(Data(installationId.utf8), to: &value)
    append(Data(requestId.utf8), to: &value)
    append(Data(String(Int64(issuedAt.timeIntervalSince1970)).utf8), to: &value)
    append(Data(SHA256.hash(data: Data(credential.utf8))), to: &value)
    append(Data(keyId.utf8), to: &value)
    if let signedTransactionInfo {
      append(Data(SHA256.hash(data: Data(signedTransactionInfo.utf8))), to: &value)
    }
    return Self(encoded: value)
  }

  private static func append(_ field: Data, to value: inout Data) {
    var length = UInt32(field.count).bigEndian
    withUnsafeBytes(of: &length) { value.append(contentsOf: $0) }
    value.append(field)
  }
}

enum DeviceSessionProofError: LocalizedError {
  case appAttestUnavailable
  case appAttestTimedOut
  case hostedProofOperationInProgress
  case secureEnclaveUnavailable
  case missingRenewableCredential

  var errorDescription: String? {
    switch self {
    case .appAttestUnavailable: "This device could not create the hosted security proof. Restart PumpSync and try again."
    case .appAttestTimedOut: "The hosted security proof took too long. PumpSync will try again later."
    case .hostedProofOperationInProgress: "Another PumpSync security operation is already in progress. Try again shortly."
    case .secureEnclaveUnavailable: "This device does not provide the Secure Enclave key required for self-hosted access."
    case .missingRenewableCredential: "The renewable session credential is missing. Reconnect and try again."
    }
  }
}
