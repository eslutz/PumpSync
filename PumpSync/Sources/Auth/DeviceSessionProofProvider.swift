import CryptoKit
import DeviceCheck
import Foundation

@MainActor
protocol DeviceSessionProofProviding {
  func hostedEnrollment(
    challenge: SessionChallengeResponse,
    installationId: String,
    existingSession: BackendSessionResponse?
  ) async throws -> HostedDeviceEnrollment

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

@MainActor
final class DeviceSessionProofProvider: DeviceSessionProofProviding {
  private static let secureEnclaveKeyAccount = "device-proof.secure-enclave-p256.v1"
  private static let appAttestKeyAccount = "device-proof.app-attest-key-id.v1"

  private let keychain: SecureKeychainStore
  private let now: () -> Date
  private let appAttest: DCAppAttestService

  init(
    keychain: SecureKeychainStore,
    now: @escaping () -> Date = Date.init,
    appAttest: DCAppAttestService = .shared
  ) {
    self.keychain = keychain
    self.now = now
    self.appAttest = appAttest
  }

  func hostedEnrollment(
    challenge: SessionChallengeResponse,
    installationId: String,
    existingSession: BackendSessionResponse?
  ) async throws -> HostedDeviceEnrollment {
    guard appAttest.isSupported else {
      throw DeviceSessionProofError.appAttestUnavailable
    }

    let requestId = UUID().uuidString
    let issuedAt = now()
    if existingSession?.protocolVersion == 2,
       let keyData = try keychain.readData(account: Self.appAttestKeyAccount),
       let keyId = String(data: keyData, encoding: .utf8),
       !keyId.isEmpty {
      let payload = DeviceProofPayload(
        operation: "enroll",
        path: "/api/v1/subscription/session",
        installationId: installationId,
        requestId: requestId,
        issuedAt: issuedAt,
        credential: challenge.challengeToken
      )
      let assertion = try await appAttest.generateAssertion(
        keyId,
        clientDataHash: Data(SHA256.hash(data: payload.encoded))
      )
      return HostedDeviceEnrollment(
        requestId: requestId,
        issuedAt: issuedAt,
        challengeToken: challenge.challengeToken,
        keyId: keyId,
        attestationObject: nil,
        assertion: assertion.base64EncodedString()
      )
    }

    let keyId = try await appAttest.generateKey()
    let clientDataHash = Data(SHA256.hash(data: Data(challenge.challengeToken.utf8)))
    let attestation = try await appAttest.attestKey(keyId, clientDataHash: clientDataHash)
    try keychain.writeData(Data(keyId.utf8), account: Self.appAttestKeyAccount)
    return HostedDeviceEnrollment(
      requestId: requestId,
      issuedAt: issuedAt,
      challengeToken: challenge.challengeToken,
      keyId: keyId,
      attestationObject: attestation.base64EncodedString(),
      assertion: nil
    )
  }

  func selfHostedEnrollment(
    challenge: SessionChallengeResponse,
    installationId: String
  ) throws -> SelfHostedDeviceEnrollment {
    let key = try secureEnclaveKey()
    let issuedAt = now()
    let requestId = UUID().uuidString
    let payload = DeviceProofPayload(
      operation: "enroll",
      path: "/api/v1/self-host/session",
      installationId: installationId,
      requestId: requestId,
      issuedAt: issuedAt,
      credential: challenge.challengeToken
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

  func refreshRequest(
    session: BackendSessionResponse,
    installationId: String,
    mode: BackendAccessMode
  ) async throws -> SessionRefreshRequest {
    guard !session.refreshToken.isEmpty else {
      throw DeviceSessionProofError.missingRenewableCredential
    }
    let refreshToken = session.refreshToken

    let requestId = UUID().uuidString
    let issuedAt = now()
    let payload = DeviceProofPayload(
      operation: "refresh",
      path: "/api/v1/session/refresh",
      installationId: installationId,
      requestId: requestId,
      issuedAt: issuedAt,
      credential: refreshToken
    )
    let proof: Data
    switch mode {
    case .hosted:
      guard appAttest.isSupported,
            let keyData = try keychain.readData(account: Self.appAttestKeyAccount),
            let keyId = String(data: keyData, encoding: .utf8),
            !keyId.isEmpty
      else {
        throw DeviceSessionProofError.appAttestUnavailable
      }
      proof = try await appAttest.generateAssertion(
        keyId,
        clientDataHash: Data(SHA256.hash(data: payload.encoded))
      )
    case .selfHosted:
      proof = try secureEnclaveKey().signature(for: payload.encoded).derRepresentation
    }

    return SessionRefreshRequest(
      installationId: installationId,
      refreshToken: refreshToken,
      requestId: requestId,
      issuedAt: issuedAt,
      proof: proof.base64EncodedString()
    )
  }

  private func secureEnclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
    guard SecureEnclave.isAvailable else {
      throw DeviceSessionProofError.secureEnclaveUnavailable
    }

    if let stored = try keychain.readData(account: Self.secureEnclaveKeyAccount) {
      do {
        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: stored)
      } catch {
        try? keychain.delete(account: Self.secureEnclaveKeyAccount)
      }
    }

    let key = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false)
    try keychain.writeData(key.dataRepresentation, account: Self.secureEnclaveKeyAccount)
    return key
  }

  private static func subjectPublicKeyInfo(_ x963: Data) -> Data {
    // DER SubjectPublicKeyInfo prefix for a P-256 uncompressed public point.
    let prefix: [UInt8] = [
      0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
      0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00
    ]
    return Data(prefix) + x963
  }
}

struct DeviceProofPayload: Equatable {
  let encoded: Data

  init(
    operation: String,
    path: String,
    installationId: String,
    requestId: String,
    issuedAt: Date,
    credential: String
  ) {
    var value = Data()
    Self.append(Data("PumpSync.DeviceSession.v2".utf8), to: &value)
    Self.append(Data(operation.utf8), to: &value)
    Self.append(Data(path.utf8), to: &value)
    Self.append(Data(installationId.utf8), to: &value)
    Self.append(Data(requestId.utf8), to: &value)
    Self.append(Data(String(Int64(issuedAt.timeIntervalSince1970)).utf8), to: &value)
    Self.append(Data(SHA256.hash(data: Data(credential.utf8))), to: &value)
    encoded = value
  }

  private static func append(_ field: Data, to value: inout Data) {
    var length = UInt32(field.count).bigEndian
    withUnsafeBytes(of: &length) { value.append(contentsOf: $0) }
    value.append(field)
  }
}

enum DeviceSessionProofError: LocalizedError {
  case appAttestUnavailable
  case secureEnclaveUnavailable
  case missingRenewableCredential

  var errorDescription: String? {
    switch self {
    case .appAttestUnavailable:
      return "This device could not create the hosted security proof. Restart PumpSync and try again."
    case .secureEnclaveUnavailable:
      return "This device does not provide the Secure Enclave key required for self-hosted access."
    case .missingRenewableCredential:
      return "The renewable session credential is missing. Reconnect and try again."
    }
  }
}
