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
    do {
      guard let data = try keychain.readData(account: Self.account) else {
        return nil
      }

      let session = try JSONCodec.decoder.decode(BackendSessionResponse.self, from: data)
      guard isValid(session) else {
        try? delete()
        return nil
      }

      return session
    } catch {
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
