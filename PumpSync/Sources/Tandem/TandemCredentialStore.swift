import Foundation
import Observation

@MainActor
@Observable
final class TandemCredentialStore {
  private static let account = "tandem-source-credentials"
  private static let validationAccount = "tandem-source-credential-validation"

  private let keychain: SecureKeychainStore
  private(set) var revision = 0
  private var observedCredentials: TandemCredentials?
  private var observedValidation: Date?
  private var observedAccountId: UUID?
  private var validationInvalidatedInMemory = false
  private(set) var accountId: UUID?
  private(set) var ownershipAvailable = false
  private(set) var hasStoredCredentials = false
  private(set) var hasValidatedCredentials = false
  private(set) var validatedAt: Date?
  private(set) var redactedUsername: String?

  init(keychain: SecureKeychainStore) {
    self.keychain = keychain
    refreshStatus()
  }

  private func observe(_ credentials: TandemCredentials?) {
    if observedCredentials != credentials || observedValidation != validatedAt || observedAccountId != accountId {
      revision &+= 1
      observedCredentials = credentials
      observedValidation = validatedAt
      observedAccountId = accountId
    }
  }

  func load() throws -> TandemCredentials? {
    guard let data = try keychain.readData(account: Self.account) else {
      ownershipAvailable = true
      accountId = nil
      hasStoredCredentials = false
      hasValidatedCredentials = false
      validatedAt = nil
      redactedUsername = nil
      observe(nil)
      return nil
    }

    let credentials = try JSONDecoder().decode(TandemCredentials.self, from: data)
    hasStoredCredentials = true
    redactedUsername = credentials.redactedUsername
    refreshValidationStatus(for: credentials)
    observe(credentials)
    return credentials
  }

  func saveValidated(_ credentials: TandemCredentials, validatedAt: Date = Date()) throws {
    // Establish unvalidated ownership first. A failed credential/final-validation
    // write must never let an older validated record bless a changed password.
    let previousCredentials = try load()
    guard ownershipAvailable else { throw KeychainStoreError.invalidData }
    let owner = previousCredentials?.username == credentials.username
      && previousCredentials?.region == credentials.region ? accountId ?? UUID() : UUID()
    let pending = TandemCredentialValidationRecord(username: credentials.username, region: credentials.region, accountId: owner, status: .unvalidated, validatedAt: nil)
    defer { refreshStatus() }
    validationInvalidatedInMemory = true
    try keychain.writeData(try JSONEncoder().encode(pending), account: Self.validationAccount)
    try keychain.writeData(try JSONEncoder().encode(credentials), account: Self.account)
    let validated = TandemCredentialValidationRecord(username: credentials.username, region: credentials.region, accountId: owner, status: .validated, validatedAt: validatedAt)
    try keychain.writeData(try JSONEncoder().encode(validated), account: Self.validationAccount)
    validationInvalidatedInMemory = false
  }

  func delete() throws {
    // Attempt both deletions independently: bailing out after the first
    // failure could leave the validation record (which holds the username)
    // orphaned in the Keychain while the UI reports credentials removed.
    var firstError: Error?
    do {
      try keychain.delete(account: Self.account)
    } catch {
      firstError = error
    }

    do {
      try keychain.delete(account: Self.validationAccount)
    } catch {
      firstError = firstError ?? error
    }

    refreshStatus()
    if let firstError {
      throw firstError
    }
  }

  /// Called when the backend reports Tandem rejected the stored credentials
  /// (a sync-time 424): the credentials stay stored, but they must be
  /// re-validated before the next sync so the UI directs the user to the
  /// credential form instead of looping on a failing sync.
  func invalidateValidation() {
    validationInvalidatedInMemory = true
    do {
      if let credentials = observedCredentials, let accountId {
        let record = TandemCredentialValidationRecord(username: credentials.username, region: credentials.region, accountId: accountId, status: .unvalidated, validatedAt: nil)
        try keychain.writeData(try JSONEncoder().encode(record), account: Self.validationAccount)
      }
    } catch {
      // Keep this process blocked even if durable invalidation is unavailable.
      // Preserve the ownership record rather than deleting the account UUID.
    }

    hasValidatedCredentials = false
    validatedAt = nil
    observe(observedCredentials)
  }

  func refreshStatus() {
    do {
      _ = try load()
    } catch {
      ownershipAvailable = false
      hasStoredCredentials = false
      hasValidatedCredentials = false
      validatedAt = nil
      redactedUsername = nil
      observe(nil)
    }
  }

  private func refreshValidationStatus(for credentials: TandemCredentials) {
    do {
      guard let data = try keychain.readData(account: Self.validationAccount) else {
        ownershipAvailable = true
        accountId = nil
        hasValidatedCredentials = false
        validatedAt = nil
        return
      }
      var record = try JSONDecoder().decode(TandemCredentialValidationRecord.self, from: data)
      guard record.username == credentials.username, record.region == credentials.region else {
        ownershipAvailable = true
        accountId = nil
        hasValidatedCredentials = false
        validatedAt = nil
        return
      }
      // Upgrade a readable legacy validation record durably before use. This
      // does not establish ownership of any previously unbound history cursor.
      if record.accountId == nil {
        record.accountId = UUID()
        try keychain.writeData(try JSONEncoder().encode(record), account: Self.validationAccount)
      }
      ownershipAvailable = true
      accountId = record.accountId
      hasValidatedCredentials = record.status == .validated && record.validatedAt != nil && !validationInvalidatedInMemory
      validatedAt = hasValidatedCredentials ? record.validatedAt : nil
    } catch {
      ownershipAvailable = false
      hasValidatedCredentials = false
      validatedAt = nil
    }
  }
}

private struct TandemCredentialValidationRecord: Codable {
  enum Status: String, Codable { case validated, unvalidated }
  let username: String
  let region: String
  var accountId: UUID?
  let status: Status
  let validatedAt: Date?

  init(username: String, region: String, accountId: UUID, status: Status, validatedAt: Date?) {
    self.username = username
    self.region = region
    self.accountId = accountId
    self.status = status
    self.validatedAt = validatedAt
  }

  private enum CodingKeys: String, CodingKey { case username, region, accountId, status, validatedAt }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    username = try container.decode(String.self, forKey: .username)
    region = try container.decode(String.self, forKey: .region)
    accountId = try container.decodeIfPresent(UUID.self, forKey: .accountId)
    validatedAt = try container.decodeIfPresent(Date.self, forKey: .validatedAt)
    status = try container.decodeIfPresent(Status.self, forKey: .status) ?? (validatedAt == nil ? .unvalidated : .validated)
  }
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
