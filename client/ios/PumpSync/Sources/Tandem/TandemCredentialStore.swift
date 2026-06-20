import Foundation
import Observation

@MainActor
@Observable
final class TandemCredentialStore {
  private static let account = "tandem-source-credentials"
  private static let validationAccount = "tandem-source-credential-validation"

  private let keychain: SecureKeychainStore
  private(set) var hasStoredCredentials = false
  private(set) var hasValidatedCredentials = false
  private(set) var validatedAt: Date?
  private(set) var redactedUsername: String?

  init(keychain: SecureKeychainStore) {
    self.keychain = keychain
    refreshStatus()
  }

  func load() throws -> TandemCredentials? {
    guard let data = try keychain.readData(account: Self.account) else {
      hasStoredCredentials = false
      hasValidatedCredentials = false
      validatedAt = nil
      redactedUsername = nil
      return nil
    }

    let credentials = try JSONDecoder().decode(TandemCredentials.self, from: data)
    hasStoredCredentials = true
    redactedUsername = credentials.redactedUsername
    refreshValidationStatus(for: credentials)
    return credentials
  }

  func saveValidated(_ credentials: TandemCredentials, validatedAt: Date = Date()) throws {
    let data = try JSONEncoder().encode(credentials)
    try keychain.writeData(data, account: Self.account)
    try keychain.writeData(
      try JSONEncoder().encode(TandemCredentialValidationRecord(username: credentials.username, region: credentials.region, validatedAt: validatedAt)),
      account: Self.validationAccount
    )
    hasStoredCredentials = true
    hasValidatedCredentials = true
    self.validatedAt = validatedAt
    redactedUsername = credentials.redactedUsername
  }

  func delete() throws {
    try keychain.delete(account: Self.account)
    try keychain.delete(account: Self.validationAccount)
    hasStoredCredentials = false
    hasValidatedCredentials = false
    validatedAt = nil
    redactedUsername = nil
  }

  func refreshStatus() {
    do {
      _ = try load()
    } catch {
      hasStoredCredentials = false
      hasValidatedCredentials = false
      validatedAt = nil
      redactedUsername = nil
    }
  }

  private func refreshValidationStatus(for credentials: TandemCredentials) {
    do {
      guard
        let data = try keychain.readData(account: Self.validationAccount),
        let record = try? JSONDecoder().decode(TandemCredentialValidationRecord.self, from: data),
        record.username == credentials.username,
        record.region == credentials.region
      else {
        hasValidatedCredentials = false
        validatedAt = nil
        return
      }

      hasValidatedCredentials = true
      validatedAt = record.validatedAt
    } catch {
      hasValidatedCredentials = false
      validatedAt = nil
    }
  }
}

private struct TandemCredentialValidationRecord: Codable {
  let username: String
  let region: String
  let validatedAt: Date
}

#if DEBUG
extension TandemCredentialStore {
  func applyScreenshotStatus(redactedUsername: String, validatedAt: Date) {
    hasStoredCredentials = true
    hasValidatedCredentials = true
    self.validatedAt = validatedAt
    self.redactedUsername = redactedUsername
  }
}
#endif
