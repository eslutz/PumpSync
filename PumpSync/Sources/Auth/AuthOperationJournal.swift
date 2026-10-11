import CryptoKit
import Foundation

/// Device-only recovery metadata. This is never part of the backend wire contract.
struct AuthOperationJournal: Codable {
  enum Kind: String, Codable { case enrollment, refresh }
  enum Phase: String, Codable { case prepared, submitted, responseReceived }
  enum FinalProofState: String, Codable { case registered, unchanged }
  let operationID: UUID
  let kind: Kind
  let generation: UUID
  let binding: AuthConnectionBinding
  let sourceIdentity: AuthConnectionIdentity?
  let sourceFingerprint: String?
  let proofRequestID: String
  let proofKeyID: String?
  var phase: Phase
  var target: StoredAuthConnection?
  var finalProofState: FinalProofState? = nil
  var inheritedUncertainty: SourceUncertainty? = nil

  /// A successor's prepared/rejected phase cannot make this consumed source
  /// usable. Ownership remains explicit even as the operation ID changes.
  struct SourceUncertainty: Codable, Equatable {
    let generation: UUID
    let binding: AuthConnectionBinding
    let identity: AuthConnectionIdentity?
    let fingerprint: String?
  }

  var capturedSource: SourceUncertainty {
    SourceUncertainty(generation: generation, binding: binding, identity: sourceIdentity, fingerprint: sourceFingerprint)
  }

  static func fingerprint(_ connection: AuthenticatedConnection?) throws -> String? {
    guard let connection else { return nil }
    // Match the actual Keychain representation, including its date precision.
    // Sort only after encoding so credentials/provenance/identity stay exact.
    let stored = try JSONCodec.encoder.encode(StoredAuthConnection(session: connection.session, identity: connection.identity))
    let object = try JSONSerialization.jsonObject(with: stored)
    let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return Data(SHA256.hash(data: canonical)).base64EncodedString()
  }
}

struct AuthInvalidationState: Codable {
  static let initialGeneration = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
  let generation: UUID
  let invalidated: Bool
}

enum AuthCommitError: LocalizedError {
  case operationReplaced
  case uncertainSubmission
  case commitPending
  case invalidationIncomplete
  case proofStateReplaced

  var errorDescription: String? {
    switch self {
    case .operationReplaced: "The connection changed before authentication completed."
    case .uncertainSubmission: "The connection request may have completed. A fresh authenticated connection is required."
    case .commitPending: "Your confirmed connection is waiting for secure storage. Try again after unlocking the device."
    case .invalidationIncomplete: "Disconnection could not be saved. Keep PumpSync open and retry after unlocking the device."
    case .proofStateReplaced: "The connection security state changed before authentication completed."
    }
  }
}
