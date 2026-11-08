import XCTest
@testable import PumpSync

final class DiagnosticPresentationTests: XCTestCase {
  func testReportPreservesWindowAndUnitsButExcludesUnrecognizedFields() throws {
    let report = NativeDiagnosticReport.make(from: [
      "timeStampBegin": "2026-11-05T00:00:00Z", "timeStampEnd": "2026-11-06T00:00:00Z",
      "applicationTimeMetrics": ["cumulativeForegroundTime": "15 sec"],
      "cpuMetrics": ["cumulativeCPUTime": "1 sec", "privateMarker": "12345", "password": "secret-marker"],
      "applicationLaunchMetrics": ["histogrammedTimeToFirstDraw": ["histogramValue": ["bucket0": ["bucketStart": "0 ms", "bucketEnd": "309 ms", "bucketCount": 1]]]],
      "rawHealthData": ["insulin": 12]
    ])
    XCTAssertNotNil(report.windowStart)
    XCTAssertEqual(report.windowEnd?.timeIntervalSince(report.windowStart!), 24 * 60 * 60)
    XCTAssertEqual(report.measurements["Foreground time"], "15 sec")
    XCTAssertEqual(report.measurements["CPU time"], "1 sec")
    XCTAssertFalse(report.measurements.keys.contains { $0.localizedCaseInsensitiveContains("average") })
    XCTAssertTrue(report.json.contains("309 ms"))
    for value in ["privateMarker", "12345", "secret-marker", "password", "rawHealthData"] { XCTAssertFalse(report.json.contains(value), value) }
  }

  func testTimestampOnlyReportDoesNotInventZeroMeasurements() {
    let report = NativeDiagnosticReport.make(from: ["timeStampBegin": "2026-11-05T00:00:00Z", "timeStampEnd": "2026-11-06T00:00:00Z"])
    XCTAssertTrue(report.measurements.isEmpty)
    XCTAssertTrue(MetricKitDiagnosticsCollector.reportSummary(report).contains("No supported summary measurements"))
  }

  func testLegacyAttemptDecodesMissingCountsAndScopeAsUnavailable() throws {
    let legacy = #"{"operationID":"11111111-1111-1111-1111-111111111111","trigger":"manual","startedAt":0,"stage":"recovering"}"#
    let attempt = try JSONDecoder().decode(SyncAttempt.self, from: Data(legacy.utf8))
    XCTAssertNil(attempt.historyScopeID)
    XCTAssertNil(attempt.returnedCount)
    XCTAssertNil(attempt.importedCount)
    let entry = DiagnosticEntry(source: .sync, severity: .info, title: "Owned sync attempt", message: nil, syncAttempt: attempt)
    XCTAssertEqual(DiagnosticPresentation.title(for: entry), "Manual sync recovering")
    XCTAssertEqual(DiagnosticPresentation.summary(for: entry), "Counts not recorded for this stage.")
  }

  func testHistorySeparatesLatestScopedAttemptFromLastSuccess() {
    let metadata = SyncMetadata(lastAttemptAt: Date(timeIntervalSince1970: 10), lastSuccessfulSyncAt: Date(timeIntervalSince1970: 20), lastSampleCount: 4, lastImportedCount: 3, lastErrorMessage: nil)
    var current = SyncAttempt(operationID: UUID(), trigger: .manual, startedAt: Date(timeIntervalSince1970: 30), stage: .terminal, outcome: .failed)
    current.historyScopeID = metadata.historyScopeID
    var other = current
    other.historyScopeID = UUID()
    let summary = SyncHistoryPresentation(metadata: metadata, attempts: [other, current])
    XCTAssertEqual(summary.lastAttempt, current.startedAt)
    XCTAssertEqual(summary.lastSuccess, metadata.lastSuccessfulSyncAt)
    XCTAssertEqual(summary.imported, 3)
    XCTAssertEqual(summary.countsSummary, "4 records received · 3 samples saved")
    var partial = metadata
    partial.lastPermissionSkippedCount = 1
    XCTAssertEqual(SyncHistoryPresentation(metadata: partial, attempts: [current]).countsSummary,
      "4 records received · 3 samples saved · 1 awaiting Health access")
  }
}

@MainActor
final class ProtectedNativeDiagnosticsTests: XCTestCase {
  func testFirstWriteFailureCanResumeMigrationWithoutRestarting() throws {
    let suite = "RecoverDiagnostics.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let legacy = NativeDiagnosticEntry(kind: .performance, title: "Preserve", summary: "legacy", appVersion: "1", buildNumber: "1")
    defaults.set(try JSONEncoder().encode([legacy]), forKey: "native-diagnostics")
    try Data("block directory creation".utf8).write(to: directory)
    let store = NativeDiagnosticsStore(defaults: defaults, directory: directory)
    XCTAssertNotNil(store.storageMessage)
    XCTAssertNotNil(defaults.data(forKey: "native-diagnostics"))
    try FileManager.default.removeItem(at: directory)
    store.reloadIfUnavailable()
    XCTAssertNil(store.storageMessage)
    XCTAssertEqual(store.entries.count, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("reports.json").path))
    XCTAssertNil(defaults.data(forKey: "native-diagnostics"))
  }

  func testLegacyMigrationAndClearPreserveOtherStores() throws {
    let suite = "ProtectedDiagnostics.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    let legacy = NativeDiagnosticEntry(kind: .performance, title: "Legacy", summary: "password=private-marker", appVersion: "1", buildNumber: "1")
    defaults.set(try JSONEncoder().encode([legacy]), forKey: "native-diagnostics")
    defaults.set("keep", forKey: "sync-metadata-test")
    let events = DiagnosticsLogStore(defaults: defaults)
    events.record(source: .sync, title: "Keep event")
    let store = NativeDiagnosticsStore(defaults: defaults, directory: directory)
    XCTAssertEqual(store.entries.count, 1)
    XCTAssertNil(store.entries[0].report)
    XCTAssertNil(defaults.data(forKey: "native-diagnostics"))
    XCTAssertTrue(DiagnosticPresentation.export(store.entries[0]).contains("Legacy summary only"))
    XCTAssertFalse(DiagnosticPresentation.export(store.entries[0]).contains("private-marker"))
    XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    XCTAssertEqual(NativeDiagnosticsStore(defaults: defaults, directory: directory).entries.count, 1)
    store.clear()
    XCTAssertTrue(NativeDiagnosticsStore(defaults: defaults, directory: directory).entries.isEmpty)
    XCTAssertEqual(defaults.string(forKey: "sync-metadata-test"), "keep")
    XCTAssertEqual(DiagnosticsLogStore(defaults: defaults).entries.count, 1)
  }
}
