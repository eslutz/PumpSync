import XCTest
@testable import PumpSync

@MainActor
final class DiagnosticsLogStoreTests: XCTestCase {
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
    let store = DiagnosticsLogStore()

    store.record(source: .sync, title: "First")
    store.record(source: .sync, title: "Second")

    XCTAssertEqual(store.entries.map(\.title), ["Second", "First"])
  }
}
