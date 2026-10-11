import Foundation

/// Local storage provenance. Never decode this identity from a backend response.
struct AuthConnectionBinding: Codable, Equatable {
  let backendIdentity: String
  let mode: BackendAccessMode
  let installationId: String
  let purpose: AuthPurpose
}

struct AuthConnectionIdentity: Codable, Equatable {
  let id: UUID
  let binding: AuthConnectionBinding
}

struct AuthenticatedConnection: Equatable {
  let session: BackendSessionResponse
  let identity: AuthConnectionIdentity
}

enum AuthSessionInstallation {
  case enrollment
  case verifiedRefresh(source: AuthenticatedConnection)
}

enum AuthConnectionError: Error {
  case bindingMismatch
  case sourceReplaced
}

/// A flat Keychain record retains the protocol response fields for older readers.
/// Network decoding continues to use BackendSessionResponse alone.
struct StoredAuthConnection: Codable {
  let session: BackendSessionResponse
  let identity: AuthConnectionIdentity?

  private enum CodingKeys: String, CodingKey { case localConnectionIdentity }

  init(session: BackendSessionResponse, identity: AuthConnectionIdentity?) {
    self.session = session
    self.identity = identity
  }

  init(from decoder: Decoder) throws {
    session = try BackendSessionResponse(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // A present but malformed/null identity must never be treated as legacy.
    identity = container.contains(.localConnectionIdentity)
      ? try container.decode(AuthConnectionIdentity.self, forKey: .localConnectionIdentity)
      : nil
  }

  func encode(to encoder: Encoder) throws {
    try session.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(identity, forKey: .localConnectionIdentity)
  }
}
