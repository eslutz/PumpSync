import XCTest
@testable import PumpSync

@MainActor
final class CredentialRevisionTests: XCTestCase {
  func testAccountOwnershipSurvivesInvalidationRestartAndPasswordRevalidation() throws {
    let keychain = SecureKeychainStore(service: "AccountOwnershipTests.\(UUID().uuidString)")
    defer { try? keychain.deleteAll() }
    let credentials = TandemCredentials(username: "owner@example.com", password: "one", region: "us")
    let store = TandemCredentialStore(keychain: keychain)
    try store.saveValidated(credentials)
    func record() throws -> [String: Any] {
      let data = try XCTUnwrap(keychain.readData(account: "tandem-source-credential-validation"))
      return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    let originalID = try XCTUnwrap(record()["accountId"] as? String)
    XCTAssertNotNil(UUID(uuidString: originalID))
    store.invalidateValidation()
    XCTAssertEqual(try record()["accountId"] as? String, originalID)
    XCTAssertEqual(try record()["status"] as? String, "unvalidated")
    let restarted = TandemCredentialStore(keychain: keychain)
    XCTAssertFalse(restarted.hasValidatedCredentials)
    try restarted.saveValidated(.init(username: credentials.username, password: "two", region: credentials.region))
    XCTAssertEqual(try record()["accountId"] as? String, originalID)
    XCTAssertEqual(try record()["status"] as? String, "validated")
    try restarted.saveValidated(.init(username: credentials.username, password: "two", region: "eu"))
    XCTAssertNotEqual(try record()["accountId"] as? String, originalID)
    let regionalID = try XCTUnwrap(record()["accountId"] as? String)
    try restarted.delete()
    try restarted.saveValidated(.init(username: credentials.username, password: "two", region: "eu"))
    XCTAssertNotEqual(try record()["accountId"] as? String, regionalID)
  }

  func testReadsDoNotInvalidateButEditValidationAndDeletionDo() throws {
    let store = TandemCredentialStore(keychain: SecureKeychainStore(service: "CredentialRevisionTests.\(UUID().uuidString)"))
    let credentials = TandemCredentials(username: "test@example.com", password: "one", region: "us")
    let validated = Date(timeIntervalSince1970: 100)
    try store.saveValidated(credentials, validatedAt: validated)
    let revision = store.revision
    _ = try store.load()
    store.refreshStatus()
    try store.saveValidated(credentials, validatedAt: validated)
    XCTAssertEqual(store.revision, revision)
    try store.saveValidated(TandemCredentials(username: credentials.username, password: "changed", region: "us"), validatedAt: validated)
    XCTAssertGreaterThan(store.revision, revision)
    let edited = store.revision
    store.invalidateValidation()
    XCTAssertGreaterThan(store.revision, edited)
    let invalidated = store.revision
    try store.delete()
    XCTAssertGreaterThan(store.revision, invalidated)
  }
}
