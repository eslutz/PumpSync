import Foundation
import Observation

@MainActor
@Observable
final class TandemCredentialStore {
  private static let account = "tandem-source-credentials"

  private let keychain: SecureKeychainStore
  private(set) var hasStoredCredentials = false
  private(set) var redactedUsername: String?

  init(keychain: SecureKeychainStore) {
    self.keychain = keychain
    refreshStatus()
  }

  func load() throws -> TandemCredentials? {
    guard let data = try keychain.readData(account: Self.account) else {
      hasStoredCredentials = false
      redactedUsername = nil
      return nil
    }

    let credentials = try JSONDecoder().decode(TandemCredentials.self, from: data)
    hasStoredCredentials = true
    redactedUsername = credentials.redactedUsername
    return credentials
  }

  func save(_ credentials: TandemCredentials) throws {
    let data = try JSONEncoder().encode(credentials)
    try keychain.writeData(data, account: Self.account)
    hasStoredCredentials = true
    redactedUsername = credentials.redactedUsername
  }

  func delete() throws {
    try keychain.delete(account: Self.account)
    hasStoredCredentials = false
    redactedUsername = nil
  }

  func refreshStatus() {
    do {
      _ = try load()
    } catch {
      hasStoredCredentials = false
      redactedUsername = nil
    }
  }
}
