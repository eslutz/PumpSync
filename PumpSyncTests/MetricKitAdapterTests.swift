import MetricKit
import XCTest
@testable import PumpSync

final class MetricKitAdapterTests: XCTestCase {
  private let window = DateInterval(start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 2_000))

  func testTypedMetricsNormalizeUnitsAndPreserveVersionAndWindow() throws {
    guard #available(iOS 27.0, *) else { throw XCTSkip("Typed MetricKit reports require iOS 27.") }
    let cpu = try decode(CPUTimeMetric.self, fields: ["value": ["value": 2.5, "unit": "min"]])
    let foreground = try decode(TotalForegroundTimeMetric.self, fields: ["value": ["value": 30, "unit": "s"]])
    let writes = try decode(LogicalDiskWritesMetric.self, fields: ["value": ["value": 2, "unit": "MB"]])
    let entry = MetricKitReportAdapter.performanceEntry(
      metrics: [.cpuTime(cpu), .totalForegroundTime(foreground), .logicalDiskWrites(writes)],
      window: window, version: "1.0 (multiple versions)", build: "54"
    )
    let report = try XCTUnwrap(entry.report)
    XCTAssertEqual(entry.timestamp, window.end)
    XCTAssertEqual(report.windowStart, window.start)
    XCTAssertEqual(report.windowEnd, window.end)
    XCTAssertEqual(entry.appVersion, "1.0 (multiple versions)")
    XCTAssertEqual(entry.buildNumber, "54")
    XCTAssertEqual(report.measurements["CPU time"], "150 sec")
    XCTAssertEqual(report.measurements["Foreground time"], "30 sec")
    XCTAssertEqual(report.measurements["Disk writes"], "2000000 B")
  }

  func testEmptyReportDoesNotInventZeroMeasurements() throws {
    guard #available(iOS 27.0, *) else { throw XCTSkip("Typed MetricKit reports require iOS 27.") }
    let entry = MetricKitReportAdapter.performanceEntry(metrics: [], window: window)
    XCTAssertTrue(try XCTUnwrap(entry.report).measurements.isEmpty)
    XCTAssertTrue(entry.summary.contains("No supported summary measurements"))
    XCTAssertEqual(entry.report?.windowStart, window.start)
    XCTAssertEqual(entry.report?.windowEnd, window.end)
  }

  func testTypedDiagnosticKeepsSafeStackFieldsAndExcludesUnknownMetadata() throws {
    guard #available(iOS 27.0, *) else { throw XCTSkip("Typed MetricKit reports require iOS 27.") }
    let diagnostic = try decode(HangDiagnostic.self, fields: [
      "hangDuration": ["value": 2.5, "unit": "s"],
      "callStackTree": [
        "callStackThreads": [["threadAttributed": true, "rootFrames": [[
          "binaryUUID": "01234567-89AB-CDEF-0123-456789ABCDEF", "address": 100,
          "sampleCount": 2, "subFrames": [], "account": "private-account-fixture"
        ]]]],
        "binaryInfo": [], "callStackPerThread": true
      ],
      "unknownField": "private-account-fixture"
    ])
    let entry = MetricKitReportAdapter.diagnosticEntry(result: .hang(diagnostic), window: window, version: "1", build: "54")
    let report = try XCTUnwrap(entry.report)
    XCTAssertEqual(entry.kind, .hang)
    XCTAssertTrue(report.json.contains("2.5 sec"))
    XCTAssertTrue(report.json.contains("01234567-89AB-CDEF-0123-456789ABCDEF"))
    XCTAssertFalse(report.json.contains("private-account-fixture"))
    XCTAssertFalse(report.json.contains("unknownField"))
    XCTAssertFalse(report.json.contains("binaryInfo"))
  }

  func testLegacyNormalizationMatchesTypedCommonMeasurements() throws {
    guard #available(iOS 27.0, *) else { throw XCTSkip("Typed MetricKit reports require iOS 27.") }
    let cpu = try decode(CPUTimeMetric.self, fields: ["value": ["value": 2.5, "unit": "s"]])
    let modern = MetricKitReportAdapter.performanceEntry(metrics: [.cpuTime(cpu)], window: window)
    let legacy = NativeDiagnosticReport.make(from: [
      "cpuMetrics": ["cumulativeCPUTime": "2.5 sec"],
      "unknownSystemField": ["account": "private-account-fixture"]
    ], windowStart: window.start, windowEnd: window.end)
    XCTAssertEqual(modern.report, legacy)
    XCTAssertFalse(legacy.json.contains("private-account-fixture"))
  }

  func testTerminationAndSuspendedMemoryKeepLegacyRecoveryEvidence() throws {
    guard #available(iOS 27.0, *) else { throw XCTSkip("Typed MetricKit reports require iOS 27.") }
    let foreground: [String: Int] = ["normalTerminationCount": 1, "memoryLimitTerminationCount": 2,
      "badAccessTerminationCount": 3, "abnormalTerminationCount": 4, "illegalInstructionTerminationCount": 5, "watchdogTerminationCount": 6]
    var background = foreground
    background.merge(["highCPUTerminationCount": 7, "systemPressureTerminationCount": 8,
      "fileLockTerminationCount": 9, "taskTimeoutTerminationCount": 10]) { _, new in new }
    let memory = try decode(SuspendedMemoryMetric.self, fields: ["value": [
      "average": ["value": 2, "unit": "MB"], "count": 3, "standardDeviation": 0.5]])
    let modern = MetricKitReportAdapter.performanceEntry(metrics: [
      .foregroundTermination(try decode(ForegroundTerminationMetric.self, fields: foreground)),
      .backgroundTermination(try decode(BackgroundTerminationMetric.self, fields: background)),
      .suspendedMemory(memory)
    ], window: window)
    let legacyForeground = ["cumulativeNormalAppExitCount": 1, "cumulativeMemoryResourceLimitExitCount": 2,
      "cumulativeBadAccessExitCount": 3, "cumulativeAbnormalExitCount": 4,
      "cumulativeIllegalInstructionExitCount": 5, "cumulativeAppWatchdogExitCount": 6]
    var legacyBackground = legacyForeground
    legacyBackground.merge(["cumulativeCPUResourceLimitExitCount": 7, "cumulativeMemoryPressureExitCount": 8,
      "cumulativeSuspendedWithLockedFileExitCount": 9, "cumulativeBackgroundTaskAssertionTimeoutExitCount": 10]) { _, new in new }
    let legacy = NativeDiagnosticReport.make(from: [
      "applicationExitMetrics": ["foregroundExitData": legacyForeground, "backgroundExitData": legacyBackground],
      "memoryMetrics": ["averageSuspendedMemory": ["averageValue": "2000000 B", "sampleCount": 3, "standardDeviation": 500000]]
    ], windowStart: window.start, windowEnd: window.end)
    XCTAssertEqual(modern.report, legacy)
  }

  func testLocationAndLuminanceRetainOnlyAllowlistedAggregateValues() throws {
    guard #available(iOS 27.0, *) else { throw XCTSkip("Typed MetricKit reports require iOS 27.") }
    let duration: [String: Any] = ["value": 2, "unit": "s"]
    let location = try decode(LocationActivityTimeMetric.self, fields: [
      "bestAccuracyForNavigation": duration, "bestAccuracy": duration, "tenMeters": duration,
      "oneHundredMeter": duration, "oneKilometer": duration, "threeKilometers": duration, "reducedAccuracy": duration])
    let luminance = try decode(PixelLuminanceMetric.self, fields: ["value": [
      "average": ["value": 40, "unit": AveragePixelLuminance.baseUnit().symbol], "count": 5, "standardDeviation": 10]])
    let modern = MetricKitReportAdapter.performanceEntry(metrics: [.locationActivityTime(location), .pixelLuminance(luminance)], window: window)
    let report = try XCTUnwrap(modern.report)
    XCTAssertTrue(report.json.contains("cumulativeBestAccuracyForNavigationTime"))
    XCTAssertTrue(report.json.contains("cumulativeThreeKilometersAccuracyTime"))
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(report.json.utf8)) as? [String: Any])
    let display = try XCTUnwrap(payload["displayMetrics"] as? [String: Any])
    let average = try XCTUnwrap(display["averagePixelLuminance"] as? [String: Any])
    XCTAssertEqual(average["averageValue"] as? String, "40 apl")
    XCTAssertEqual(average["sampleCount"] as? Int, 5)
    XCTAssertEqual(average["standardDeviation"] as? Double, 10)
    XCTAssertFalse(report.json.contains("reducedAccuracy"), "New fields need an explicit export schema review")
  }

  private func decode<T: Decodable>(_ type: T.Type, fields: [String: Any]) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: fields))
  }
}
