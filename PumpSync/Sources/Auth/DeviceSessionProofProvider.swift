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
}

private struct HostedProofOperation {
  let requestId: String
}

@MainActor
final class DeviceSessionProofProvider: DeviceSessionProofProviding {
  private static let secureEnclaveKeyAccount = "device-proof.secure-enclave-p256.v1"
  private static let appAttestStateAccount = "device-proof.app-attest-state.v4"

  private let keychain: SecureKeychainStore
  private let now: () -> Date
  private let appAttest: AppAttestClient
  private var hostedProofOperation: HostedProofOperation?

  init(
    keychain: SecureKeychainStore,
    now: @escaping () -> Date = Date.init,
    appAttest: AppAttestClient = LiveAppAttestClient()
  ) {
    self.keychain = keychain
    self.now = now
    self.appAttest = appAttest
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
    var state = initialState
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
        preparation: .generated
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
        requestId: requestId
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
    if state?.phase == .attestationPrepared {
      try clearState()
      state = nil
    }

    let keyId: String
    if let state, state.phase == .attesting {
      keyId = state.keyId
    } else {
      keyId = try await appAttest.generateKey()
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
      attestation = try await appAttest.attestKey(keyId, clientDataHash: payload.hash)
    } catch AppAttestClientError.serverUnavailable {
      throw AppAttestClientError.serverUnavailable
    } catch {
      try? clearState()
      throw error
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
    try saveState(state)
    return true
  }

  func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool {
    guard let state = try loadState(), state.keyId == keyId else { return false }
    guard (state.phase == .registrationUnknown || state.phase == .registeredAssertionSubmitted),
          state.pendingEnrollment?.enrollment.requestId == requestId else {
      return false
    }
    defer { _ = releaseHostedProofOperation(requestId: requestId) }
    try saveState(PersistedAppAttestKeyState(keyId: keyId, phase: .registered, pendingEnrollment: nil))
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
      try clearState()
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
      try clearState()
      return true
    case .reconciliationPrepared:
      defer { _ = releaseHostedProofOperation(requestId: requestId) }
      state.phase = .registrationUnknown
      state.pendingEnrollment = nil
      try saveState(state)
      return true
    case .registeredAssertionPrepared:
      defer { _ = releaseHostedProofOperation(requestId: requestId) }
      state.phase = .registered
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
      assertion = try await appAttest.generateAssertion(keyId, clientDataHash: payload.hash)
    } catch AppAttestClientError.invalidKey {
      try? clearState()
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
    requestId: String
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
      )
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
    preparation: HostedDeviceProofPreparation
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
      )
    ))
    return enrollment
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
    hostedProofOperation = HostedProofOperation(requestId: requestId)
    do {
      return try await operation()
    } catch {
      _ = releaseHostedProofOperation(requestId: requestId)
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

  func refreshRequest(session: BackendSessionResponse, installationId: String, mode: BackendAccessMode) async throws -> SessionRefreshRequest {
    guard !session.refreshToken.isEmpty else { throw DeviceSessionProofError.missingRenewableCredential }
    let requestId = UUID().uuidString
    let issuedAt = now()
    let proof: Data
    switch mode {
    case .hosted:
      proof = try await withHostedProofOperation(requestId: requestId) {
        guard appAttest.isSupported, let state = try loadState() else {
          throw DeviceSessionProofError.appAttestUnavailable
        }
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
        do {
          return try await appAttest.generateAssertion(state.keyId, clientDataHash: payload.hash)
        } catch AppAttestClientError.invalidKey {
          try? clearState()
          throw AppAttestClientError.invalidKey
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
    do { return try JSONCodec.decoder.decode(PersistedAppAttestKeyState.self, from: data) }
    catch { try? clearState(); return nil }
  }

  private func saveState(_ state: PersistedAppAttestKeyState) throws {
    try keychain.writeData(try JSONCodec.encoder.encode(state), account: Self.appAttestStateAccount)
  }

  private func clearState() throws {
    try keychain.delete(account: Self.appAttestStateAccount)
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
  case hostedProofOperationInProgress
  case secureEnclaveUnavailable
  case missingRenewableCredential

  var errorDescription: String? {
    switch self {
    case .appAttestUnavailable: "This device could not create the hosted security proof. Restart PumpSync and try again."
    case .hostedProofOperationInProgress: "Another PumpSync security operation is already in progress. Try again shortly."
    case .secureEnclaveUnavailable: "This device does not provide the Secure Enclave key required for self-hosted access."
    case .missingRenewableCredential: "The renewable session credential is missing. Reconnect and try again."
    }
  }
}
