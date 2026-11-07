import XCTest
@testable import PumpSync

@MainActor
final class DiagnosticsLogStoreTests: XCTestCase {
  func testSecretRedactionIsIdempotentAcrossRepeatedExportBoundaries() {
    let value = #"password="a multiword secret" accessToken=unquoted-token user@example.com"#
    let once = DiagnosticsLogStore.redacted(value)
    XCTAssertEqual(DiagnosticsLogStore.redacted(once), once)
  }

  func testQuotedSecretsAreFullyRemovedFromPersistenceAndExports() throws {
    let suite = "QuotedSecrets.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DiagnosticsLogStore(defaults: defaults)
    store.record(source: .auth, title: "Failure", message: #"password="correct horse,battery;staple" accessToken='escaped secret phrase'"#)
    let entry = try XCTUnwrap(DiagnosticsLogStore(defaults: defaults).entries.first)
    for output in [entry.message ?? "", DiagnosticPresentation.export(entry), String(decoding: defaults.data(forKey: "diagnostics-log")!, as: UTF8.self)] {
      for secret in ["correct", "horse", "battery", "staple", "escaped", "phrase"] { XCTAssertFalse(output.contains(secret), secret) }
    }
  }

  func testRedactsNamedSecretsAndTitlesBeforePersistence() {
    let store = makeStore()
    store.record(source: .auth, title: "Failure for private@example.com", message: "password=secret-marker accessToken=access-marker authorization=Basic-secret")
    let entry = store.entries[0]
    XCTAssertFalse(entry.title.contains("private@example.com"))
    XCTAssertFalse(entry.message?.contains("secret-marker") ?? true)
    XCTAssertFalse(entry.message?.contains("access-marker") ?? true)
    XCTAssertFalse(entry.message?.contains("Basic-secret") ?? true)
  }

  func testRedactsRenewableSessionCredentialsAndChallenges() {
    let redacted = DiagnosticsLogStore.redacted(
      "refresh=psrt1.019c1234567890abcdef1234567890ab.aVeryLongRefreshSecretValue123456789 challenge=psc1.payloadPayloadPayloadPayload.signatureSignatureSignature"
    )

    XCTAssertFalse(redacted.contains("psrt1."))
    XCTAssertFalse(redacted.contains("psc1."))
    XCTAssertTrue(redacted.contains("[redacted renewable credential]"))
  }

  func testRedactsEmailAndBearerToken() {
    let redacted = DiagnosticsLogStore.redacted(
      "Authorization failed for user@example.com with Bearer eyJhbGciOi.fake-token-value-1234567890."
    )

    XCTAssertFalse(redacted.contains("user@example.com"))
    XCTAssertFalse(redacted.contains("eyJhbGciOi.fake-token-value-1234567890"))
    XCTAssertTrue(redacted.contains("[redacted email]"))
    XCTAssertTrue(redacted.contains("Bearer [redacted token]"))
  }

  func testRecordKeepsNewestEntriesFirst() {
    let store = makeStore()

    store.record(source: .sync, title: "First")
    store.record(source: .sync, title: "Second")

    XCTAssertEqual(store.entries.map(\.title), ["Second", "First"])
  }

  func testRecordCapsAtTwoHundredEntries() {
    let store = makeStore()

    for index in 0..<205 {
      store.record(source: .sync, title: "Entry \(index)")
    }

    XCTAssertEqual(store.entries.count, 200)
    XCTAssertEqual(store.entries.first?.title, "Entry 204")
    XCTAssertEqual(store.entries.last?.title, "Entry 5")
  }

  func testEntriesSurviveARelaunchAcrossTheSameDefaults() {
    let suiteName = "DiagnosticsLogStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = DiagnosticsLogStore(defaults: defaults)
    store.record(source: .sync, severity: .error, title: "Sync failed", message: "user@example.com Bearer eyJhbGciOi.fake-token-value-1234567890")

    // A fresh instance against the same defaults simulates a crash-relaunch:
    // this is the whole point of persisting the log at all.
    let relaunched = DiagnosticsLogStore(defaults: defaults)

    XCTAssertEqual(relaunched.entries.count, 1)
    XCTAssertEqual(relaunched.entries.first?.title, "Sync failed")
    XCTAssertEqual(relaunched.entries.first?.severity, .error)
    // The persisted copy must carry the same redaction as what was held in
    // memory — there's no separate persistence-time redaction path to drift.
    XCTAssertEqual(relaunched.entries.first?.message, store.entries.first?.message)
    XCTAssertFalse(relaunched.entries.first?.message?.contains("user@example.com") ?? true)
  }

  func testClearRemovesPersistedEntries() {
    let suiteName = "DiagnosticsLogStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = DiagnosticsLogStore(defaults: defaults)
    store.record(source: .sync, title: "First")

    store.clear()

    XCTAssertTrue(store.entries.isEmpty)
    XCTAssertTrue(DiagnosticsLogStore(defaults: defaults).entries.isEmpty)
  }

  private func makeStore() -> DiagnosticsLogStore {
    let suiteName = "DiagnosticsLogStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return DiagnosticsLogStore(defaults: defaults)
  }
}
