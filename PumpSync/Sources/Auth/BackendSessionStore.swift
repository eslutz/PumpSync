import Foundation

@MainActor
protocol BackendSessionPersistence {
  func readData(account: String) throws -> Data?
  func writeData(_ data: Data, account: String) throws
  func delete(account: String) throws
}

extension SecureKeychainStore: BackendSessionPersistence {}

@MainActor
final class BackendSessionStore {
  private static let account = "backend.session.current"
  private static let hostedReenrollmentAccount = "backend.session.hosted-reenrollment-pending"
  private static let refreshWindow: TimeInterval = 5 * 60

  private let keychain: any BackendSessionPersistence
  private let now: () -> Date

  init(keychain: any BackendSessionPersistence, now: @escaping () -> Date = Date.init) {
    self.keychain = keychain
    self.now = now
  }

  func loadValidSession() -> BackendSessionResponse? {
    guard let session = loadStoredSession() else {
      return nil
    }

    if isValid(session) {
      return session
    }

    if !isRenewable(session) {
      try? delete()
    }
    return nil
  }

  func loadRecoverableSession() -> BackendSessionResponse? {
    guard let session = loadStoredSession() else {
      return nil
    }

    if isValid(session) || isRenewable(session) {
      return session
    }

    try? delete()
    return nil
  }

  private func loadStoredSession() -> BackendSessionResponse? {
    let data: Data?
    do {
      data = try keychain.readData(account: Self.account)
    } catch {
      // A Keychain read failure (for example, the device has not been unlocked
      // since restart) is transient, not evidence of a corrupted session. Do not
      // delete the stored session — it may still be readable and valid later.
      return nil
    }

    guard let data else {
      return nil
    }

    do {
      let session = try JSONCodec.decoder.decode(BackendSessionResponse.self, from: data)
      return session
    } catch {
      // A decode failure means the stored data is corrupted or from an
      // incompatible format, so it is safe to discard.
      try? delete()
      return nil
    }
  }

  /// Missing data is nil. Inaccessible, malformed, mismatched, or unsuccessfully
  /// migrated storage throws so callers cannot silently enroll over it.
  func loadConnection(binding: AuthConnectionBinding) throws -> AuthenticatedConnection? {
    guard let data = try keychain.readData(account: Self.account) else { return nil }
    let stored = try JSONCodec.decoder.decode(StoredAuthConnection.self, from: data)
    guard stored.session.serviceMode == binding.mode.rawValue else {
      throw AuthConnectionError.bindingMismatch
    }
    if let identity = stored.identity {
      guard identity.binding == binding else { throw AuthConnectionError.bindingMismatch }
      return AuthenticatedConnection(session: stored.session, identity: identity)
    }
    let migrated = AuthenticatedConnection(
      session: stored.session,
      identity: AuthConnectionIdentity(id: UUID(), binding: binding)
    )
    try save(migrated)
    return migrated
  }

  func save(_ connection: AuthenticatedConnection) throws {
    let data = try JSONCodec.encoder.encode(StoredAuthConnection(session: connection.session, identity: connection.identity))
    try keychain.writeData(data, account: Self.account)
  }

  func save(_ session: BackendSessionResponse) throws {
    let data = try JSONCodec.encoder.encode(session)
    try keychain.writeData(data, account: Self.account)
  }

  func delete() throws {
    try keychain.delete(account: Self.account)
  }

  func markHostedReenrollmentPending() throws {
    try keychain.writeData(Data([1]), account: Self.hostedReenrollmentAccount)
  }

  func isHostedReenrollmentPending() -> Bool {
    (try? keychain.readData(account: Self.hostedReenrollmentAccount)) != nil
  }

  func clearHostedReenrollmentPending() throws {
    try keychain.delete(account: Self.hostedReenrollmentAccount)
  }

  func isValid(_ session: BackendSessionResponse) -> Bool {
    Self.isValid(session, at: now())
  }

  static func isValid(_ session: BackendSessionResponse, at date: Date) -> Bool {
    guard session.protocolVersion == 3, !session.accessToken.isEmpty else {
      return false
    }

    return session.expiresAt.timeIntervalSince(date) > Self.refreshWindow
  }

  func isRenewable(_ session: BackendSessionResponse) -> Bool {
    Self.isRenewable(session, at: now())
  }

  static func isRenewable(_ session: BackendSessionResponse, at date: Date) -> Bool {
    guard
      session.protocolVersion == 3,
      !session.refreshToken.isEmpty
    else {
      return false
    }

    return session.refreshTokenExpiresAt > date && session.refreshTokenAbsoluteExpiresAt > date
  }
}
