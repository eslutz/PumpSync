import XCTest
@testable import PumpSync

@MainActor
final class CredentialRevisionTests: XCTestCase {
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
