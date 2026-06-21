import XCTest
@testable import PumpSync

@MainActor
final class NativeDiagnosticsStoreTests: XCTestCase {
  func testRecordKeepsNewestEntriesFirstAndCapsAtFifty() {
    let suiteName = "NativeDiagnosticsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = NativeDiagnosticsStore(defaults: defaults)

    for index in 0..<55 {
      store.record(NativeDiagnosticEntry(
        timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
        kind: .performance,
        title: "Entry \(index)",
        summary: "Summary \(index)",
        appVersion: "1.0",
        buildNumber: "1"
      ))
    }

    XCTAssertEqual(store.entries.count, 50)
    XCTAssertEqual(store.entries.first?.title, "Entry 54")
    XCTAssertEqual(store.entries.last?.title, "Entry 5")
  }

  func testClearRemovesPersistedEntries() {
    let suiteName = "NativeDiagnosticsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = NativeDiagnosticsStore(defaults: defaults)

    store.record(NativeDiagnosticEntry(
      kind: .crash,
      title: "Crash",
      summary: "Signal 11",
      appVersion: "1.0",
      buildNumber: "1"
    ))
    store.clear()

    XCTAssertTrue(store.entries.isEmpty)
    XCTAssertTrue(NativeDiagnosticsStore(defaults: defaults).entries.isEmpty)
  }

  func testMetricKitFlattenRedactsSensitiveValues() {
    let flattened = MetricKitDiagnosticsCollector.flatten([
      "diagnosticMetaData": [
        "message": "Failure for support@example.com with Bearer eyJhbGciOi.fake-token-value-1234567890"
      ]
    ])

    let value = flattened.values.joined(separator: " ")
    XCTAssertFalse(value.contains("support@example.com"))
    XCTAssertFalse(value.contains("fake-token-value"))
    XCTAssertTrue(value.contains("[redacted email]"))
    XCTAssertTrue(value.contains("Bearer [redacted token]"))
  }
}
