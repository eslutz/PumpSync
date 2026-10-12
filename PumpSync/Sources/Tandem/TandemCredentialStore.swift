import Foundation
import Observation

@MainActor
protocol TandemCredentialPersistence {
  func readData(account: String) throws -> Data?
  func writeData(_ data: Data, account: String) throws
  func delete(account: String) throws
}

extension SecureKeychainStore: TandemCredentialPersistence {}

@MainActor
@Observable
final class TandemCredentialStore {
  private static let account = "tandem-source-credentials"
  private static let validationAccount = "tandem-source-credential-validation"

  private let keychain: any TandemCredentialPersistence
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

  init(keychain: any TandemCredentialPersistence) {
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

    let stored = try JSONDecoder().decode(TandemStoredCredentialRecord.self, from: data)
    let credentials = stored.credentials
    hasStoredCredentials = true
    redactedUsername = credentials.redactedUsername
    if stored.accountId != nil || stored.status != nil {
      guard let record = stored.validationRecord else { throw KeychainStoreError.invalidData }
      applyValidation(record)
    } else {
      refreshValidationStatus(for: credentials)
    }
    observe(credentials)
    return credentials
  }

  func saveValidated(_ credentials: TandemCredentials, validatedAt: Date = Date()) throws {
    let previousCredentials = try load()
    guard ownershipAvailable else { throw KeychainStoreError.invalidData }
    let owner = previousCredentials?.username == credentials.username
      && previousCredentials?.region == credentials.region ? accountId ?? UUID() : UUID()
    let validated = TandemCredentialValidationRecord(username: credentials.username, region: credentials.region, accountId: owner, status: .validated, validatedAt: validatedAt)
    defer { refreshStatus() }
    // Credentials, validation, and ownership commit in one Keychain upsert.
    // A failure or termination before this commit preserves the previous account.
    try persist(credentials, validation: validated)
    validationInvalidatedInMemory = false
  }

  private func persist(_ credentials: TandemCredentials, validation: TandemCredentialValidationRecord) throws {
    try keychain.writeData(try JSONEncoder().encode(TandemStoredCredentialRecord(credentials: credentials, validation: validation)), account: Self.account)
    // This legacy mirror supports older readers but is never authoritative for
    // the new format. Failure cannot undo the complete atomic credential record.
    try? keychain.writeData(try JSONEncoder().encode(validation), account: Self.validationAccount)
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
        try persist(credentials, validation: record)
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
      // Upgrade both legacy items into one durable record before publishing
      // ownership. A failed migration keeps legacy proof intact and unavailable.
      if record.accountId == nil { record.accountId = UUID() }
      try persist(credentials, validation: record)
      applyValidation(record)
    } catch {
      ownershipAvailable = false
      hasValidatedCredentials = false
      validatedAt = nil
    }
  }

  private func applyValidation(_ record: TandemCredentialValidationRecord) {
    ownershipAvailable = true
    accountId = record.accountId
    hasValidatedCredentials = record.status == .validated && record.validatedAt != nil && !validationInvalidatedInMemory
    validatedAt = hasValidatedCredentials ? record.validatedAt : nil
  }
}

/// Flat additive encoding preserves the existing TandemCredentials decoder.
/// Validation fields now share the credential item's atomic Keychain boundary.
private struct TandemStoredCredentialRecord: Codable {
  let username: String
  let password: String
  let region: String
  let accountId: UUID?
  let status: TandemCredentialValidationRecord.Status?
  let validatedAt: Date?

  var credentials: TandemCredentials { .init(username: username, password: password, region: region) }
  var validationRecord: TandemCredentialValidationRecord? {
    guard let accountId, let status else { return nil }
    return .init(username: username, region: region, accountId: accountId, status: status, validatedAt: validatedAt)
  }

  init(credentials: TandemCredentials, validation: TandemCredentialValidationRecord) {
    username = credentials.username
    password = credentials.password
    region = credentials.region
    accountId = validation.accountId
    status = validation.status
    validatedAt = validation.validatedAt
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
