import Foundation
import MetricKit

/// Projects typed system reports into the existing, explicitly allowlisted
/// export schema. Never encodes a raw MetricReport or DiagnosticReport.
@available(iOS 27.0, *)
enum MetricKitReportAdapter {
  static func performanceEntry(_ report: MetricReport) -> NativeDiagnosticEntry {
    performanceEntry(
      // The daily aggregate already includes the reporting intervals. Do not
      // add interval/state values again or fabricate zeroes for empty reports.
      metrics: report.intervalEntries.isEmpty ? [] : report.intervalEntries.fullDayEntry.values,
      window: report.timeRange,
      version: report.environment.map {
        $0.latestApplicationVersion + ($0.includesMultipleApplicationVersions ? " (multiple versions)" : "")
      } ?? "Not reported",
      build: report.environment?.applicationBuildVersion ?? "Not reported"
    )
  }

  static func performanceEntry(
    metrics: [MetricResult], window: DateInterval,
    version: String = "Not reported", build: String = "Not reported"
  ) -> NativeDiagnosticEntry {
    var groups: [String: [String: Any]] = [:]
    for metric in metrics {
      switch metric {
      case .totalForegroundTime(let metric):
        groups["applicationTimeMetrics", default: [:]]["cumulativeForegroundTime"] = duration(metric.value)
      case .totalBackgroundTime(let metric):
        groups["applicationTimeMetrics", default: [:]]["cumulativeBackgroundTime"] = duration(metric.value)
      case .cpuTime(let metric):
        groups["cpuMetrics", default: [:]]["cumulativeCPUTime"] = duration(metric.value)
      case .gpuTime(let metric):
        groups["gpuMetrics", default: [:]]["cumulativeGPUTime"] = duration(metric.value)
      case .peakMemory(let metric):
        groups["memoryMetrics", default: [:]]["peakMemoryUsage"] = bytes(metric.value)
      case .logicalDiskWrites(let metric):
        groups["diskIOMetrics", default: [:]]["cumulativeLogicalWrites"] = bytes(metric.value)
      case .totalWiFiDownload(let metric):
        groups["networkTransferMetrics", default: [:]]["cumulativeWifiDownload"] = bytes(metric.value)
      case .totalWiFiUpload(let metric):
        groups["networkTransferMetrics", default: [:]]["cumulativeWifiUpload"] = bytes(metric.value)
      case .totalCellularDownload(let metric):
        groups["networkTransferMetrics", default: [:]]["cumulativeCellularDownload"] = bytes(metric.value)
      case .totalCellularUpload(let metric):
        groups["networkTransferMetrics", default: [:]]["cumulativeCellularUpload"] = bytes(metric.value)
      case .timeToFirstDraw(let metric):
        groups["applicationLaunchMetrics", default: [:]]["histogrammedTimeToFirstDraw"] = histogram(metric.histogram)
      case .applicationResumeTime(let metric):
        groups["applicationLaunchMetrics", default: [:]]["histogrammedApplicationResumeTime"] = histogram(metric.histogram)
      case .optimizedTimeToFirstDraw(let metric):
        groups["applicationLaunchMetrics", default: [:]]["histogrammedOptimizedTimeToFirstDraw"] = histogram(metric.histogram)
      case .extendedLaunch(let metric):
        groups["applicationLaunchMetrics", default: [:]]["histogrammedExtendedLaunch"] = histogram(metric.histogram)
      case .foregroundTermination(let metric):
        groups["applicationExitMetrics", default: [:]]["foregroundExitData"] = foregroundExits(metric)
      case .backgroundTermination(let metric):
        groups["applicationExitMetrics", default: [:]]["backgroundExitData"] = backgroundExits(metric)
      case .suspendedMemory(let metric):
        groups["memoryMetrics", default: [:]]["averageSuspendedMemory"] = average(metric.value, unit: .bytes, suffix: "B")
      case .hangTime(let metric):
        groups["applicationResponsivenessMetrics", default: [:]]["histogrammedTimeToHang"] = histogram(metric.histogram)
      case .locationActivityTime(let metric):
        var values: [String: Any] = [:]
        values["cumulativeBestAccuracyForNavigationTime"] = duration(metric.bestAccuracyForNavigation)
        values["cumulativeBestAccuracyTime"] = duration(metric.bestAccuracy)
        values["cumulativeNearestTenMetersAccuracyTime"] = duration(metric.tenMeters)
        values["cumulativeHundredMetersAccuracyTime"] = duration(metric.oneHundredMeter)
        values["cumulativeKilometerAccuracyTime"] = duration(metric.oneKilometer)
        values["cumulativeThreeKilometersAccuracyTime"] = duration(metric.threeKilometers)
        groups["locationActivityMetrics"] = values
      case .pixelLuminance(let metric):
        // Apple reports average pixel luminance from 0–100 in apl units.
        groups["displayMetrics", default: [:]]["averagePixelLuminance"] = average(metric.value, unit: .baseUnit(), suffix: "apl")
      default:
        // New system fields require an explicit privacy/schema review.
        break
      }
    }
    let normalized = NativeDiagnosticReport.make(from: groups, windowStart: window.start, windowEnd: window.end)
    return NativeDiagnosticEntry(
      timestamp: window.end, kind: .performance, title: "Performance metrics",
      summary: MetricKitDiagnosticsCollector.reportSummary(normalized),
      appVersion: version, buildNumber: build, report: normalized
    )
  }

  static func diagnosticEntry(_ report: DiagnosticReport) -> NativeDiagnosticEntry {
    diagnosticEntry(
      result: report.result, window: report.timeRange,
      version: report.environment.applicationVersion, build: report.environment.applicationBuildVersion
    )
  }

  static func diagnosticEntry(
    result: DiagnosticResult, window: DateInterval, version: String, build: String
  ) -> NativeDiagnosticEntry {
    let kind: NativeDiagnosticKind
    let title: String
    let payload: [String: Any]
    switch result {
    case .crash(let diagnostic):
      kind = .crash; title = "Crash diagnostic"
      var values: [String: Any] = ["callStackTree": callStack(diagnostic.callStackTree)]
      values["exceptionType"] = diagnostic.exceptionType
      values["exceptionCode"] = diagnostic.exceptionCode
      values["signal"] = diagnostic.signal
      // Free-form exception messages, memory-region descriptions, process IDs,
      // device information and state metadata intentionally never cross here.
      payload = ["crashDiagnostics": [values]]
    case .hang(let diagnostic):
      kind = .hang; title = "Hang diagnostic"
      var values: [String: Any] = ["callStackTree": callStack(diagnostic.callStackTree)]
      values["duration"] = duration(diagnostic.hangDuration)
      payload = ["hangDiagnostics": [values]]
    case .cpuException(let diagnostic):
      kind = .cpuException; title = "CPU exception diagnostic"
      var values: [String: Any] = ["callStackTree": callStack(diagnostic.callStackTree)]
      values["totalCPUTime"] = duration(diagnostic.totalCPUTime)
      values["totalSampledTime"] = duration(diagnostic.totalSampledTime)
      payload = ["cpuExceptionDiagnostics": [values]]
    case .diskWriteException(let diagnostic):
      kind = .diagnostic; title = "Disk write diagnostic"
      var values: [String: Any] = ["callStackTree": callStack(diagnostic.callStackTree)]
      values["writesCaused"] = bytes(diagnostic.totalBytesWritten)
      payload = ["diskWriteExceptionDiagnostics": [values]]
    default:
      kind = .diagnostic; title = "Native diagnostic"
      payload = [:]
    }
    let normalized = NativeDiagnosticReport.make(
      from: payload, windowStart: window.start, windowEnd: window.end
    )
    return NativeDiagnosticEntry(
      timestamp: window.end, kind: kind, title: title,
      summary: "MetricKit delivered a native diagnostic report. Open details for retained fields.",
      appVersion: version, buildNumber: build, report: normalized
    )
  }

  private static func foregroundExits(_ metric: ForegroundTerminationMetric) -> [String: Int] {
    ["cumulativeNormalAppExitCount": metric.normalTerminationCount,
     "cumulativeMemoryResourceLimitExitCount": metric.memoryLimitTerminationCount,
     "cumulativeBadAccessExitCount": metric.badAccessTerminationCount,
     "cumulativeAbnormalExitCount": metric.abnormalTerminationCount,
     "cumulativeIllegalInstructionExitCount": metric.illegalInstructionTerminationCount,
     "cumulativeAppWatchdogExitCount": metric.watchdogTerminationCount]
  }

  private static func backgroundExits(_ metric: BackgroundTerminationMetric) -> [String: Int] {
    ["cumulativeNormalAppExitCount": metric.normalTerminationCount,
     "cumulativeMemoryResourceLimitExitCount": metric.memoryLimitTerminationCount,
     "cumulativeBadAccessExitCount": metric.badAccessTerminationCount,
     "cumulativeAbnormalExitCount": metric.abnormalTerminationCount,
     "cumulativeIllegalInstructionExitCount": metric.illegalInstructionTerminationCount,
     "cumulativeAppWatchdogExitCount": metric.watchdogTerminationCount,
     "cumulativeCPUResourceLimitExitCount": metric.highCPUTerminationCount,
     "cumulativeMemoryPressureExitCount": metric.systemPressureTerminationCount,
     "cumulativeSuspendedWithLockedFileExitCount": metric.fileLockTerminationCount,
     "cumulativeBackgroundTaskAssertionTimeoutExitCount": metric.taskTimeoutTerminationCount]
  }

  private static func average<Unit: Dimension>(_ statistics: AverageStatistics<Unit>, unit: Unit, suffix: String) -> [String: Any] {
    var values: [String: Any] = [:]
    values["averageValue"] = quantity(statistics.average.converted(to: unit).value, unit: suffix)
    if statistics.count >= 0 { values["sampleCount"] = statistics.count }
    if let deviation = statistics.standardDeviation, deviation >= 0 {
      let normalized = Measurement(value: deviation, unit: statistics.average.unit).converted(to: unit).value
      if normalized.isFinite { values["standardDeviation"] = normalized }
    }
    return values
  }

  private static func duration(_ measurement: Measurement<UnitDuration>) -> String? {
    quantity(measurement.converted(to: .seconds).value, unit: "sec")
  }

  private static func bytes(_ measurement: Measurement<UnitInformationStorage>) -> String? {
    quantity(measurement.converted(to: .bytes).value, unit: "B")
  }

  private static func quantity(_ value: Double, unit: String) -> String? {
    guard value.isFinite, value >= 0 else { return nil }
    let number = value.formatted(.number.locale(Locale(identifier: "en_US_POSIX"))
      .grouping(.never).precision(.fractionLength(0...6)))
    return unit.isEmpty ? number : "\(number) \(unit)"
  }

  private static func histogram(_ histogram: Histogram<UnitDuration>) -> [String: Any] {
    let buckets = histogram.buckets.compactMap { bucket -> [String: Any]? in
      guard let start = duration(bucket.lowerBound), let end = duration(bucket.upperBound), bucket.count >= 0 else { return nil }
      return ["bucketStart": start, "bucketEnd": end, "bucketCount": bucket.count]
    }
    return ["histogramNumBuckets": buckets.count, "histogramBuckets": buckets]
  }

  private static func callStack(_ tree: CallStackTree) -> [String: Any] {
    ["callStacks": tree.callStackThreads.map { thread in
      var result: [String: Any] = ["callStackRootFrames": thread.rootFrames.map(frame)]
      result["threadAttributed"] = thread.threadAttributed
      return result
    }]
  }

  private static func frame(_ frame: CallStackFrame) -> [String: Any] {
    var result: [String: Any] = ["subFrames": frame.subFrames.map(Self.frame)]
    result["binaryUUID"] = frame.binaryUUID?.uuidString
    result["address"] = frame.address
    result["offsetIntoBinaryTextSegment"] = frame.offsetIntoBinaryTextSegment
    result["sampleCount"] = frame.sampleCount
    return result
  }
}
