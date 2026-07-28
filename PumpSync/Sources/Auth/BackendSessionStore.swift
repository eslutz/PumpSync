import Foundation

@MainActor
final class BackendSessionStore {
  private static let account = "backend.session.v1"
  private static let refreshWindow: TimeInterval = 5 * 60

  private let keychain: SecureKeychainStore
  private let now: () -> Date

  init(keychain: SecureKeychainStore, now: @escaping () -> Date = Date.init) {
    self.keychain = keychain
    self.now = now
  }

  func loadValidSession() -> BackendSessionResponse? {
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
      guard isValid(session) else {
        try? delete()
        return nil
      }

      return session
    } catch {
      // A decode failure means the stored data is corrupted or from an
      // incompatible format, so it is safe to discard.
      try? delete()
      return nil
    }
  }

  func save(_ session: BackendSessionResponse) throws {
    let data = try JSONCodec.encoder.encode(session)
    try keychain.writeData(data, account: Self.account)
  }

  func delete() throws {
    try keychain.delete(account: Self.account)
  }

  func isValid(_ session: BackendSessionResponse) -> Bool {
    guard !session.accessToken.isEmpty else {
      return false
    }

    return session.expiresAt.timeIntervalSince(now()) > Self.refreshWindow
  }
}
