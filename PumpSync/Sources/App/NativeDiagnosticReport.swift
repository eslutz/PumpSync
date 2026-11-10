import Foundation

struct NativeDiagnosticReport: Codable, Equatable, Sendable {
  let windowStart: Date?
  let windowEnd: Date?
  let measurements: [String: String]
  let json: String

  static func make(from payload: Any, windowStart: Date? = nil, windowEnd: Date? = nil) -> NativeDiagnosticReport {
    let source = payload as? [String: Any] ?? [:]
    let groups: Set<String> = ["timeStampBegin", "timeStampEnd", "cpuMetrics", "memoryMetrics", "diskIOMetrics", "networkTransferMetrics", "applicationTimeMetrics", "applicationLaunchMetrics", "applicationResponsivenessMetrics", "cellularConditionMetrics", "applicationExitMetrics", "gpuMetrics", "displayMetrics", "animationMetrics", "locationActivityMetrics", "crashDiagnostics", "hangDiagnostics", "cpuExceptionDiagnostics", "diskWriteExceptionDiagnostics"]
    var safe = source.filter { groups.contains($0.key) }.compactMapValues(sanitize)
    if let windowStart { safe["timeStampBegin"] = DiagnosticPresentation.exactTime(windowStart) }
    if let windowEnd { safe["timeStampEnd"] = DiagnosticPresentation.exactTime(windowEnd) }
    let data = (try? JSONSerialization.data(withJSONObject: safe, options: [.sortedKeys, .prettyPrinted])) ?? Data("{}".utf8)
    let flattened = MetricKitDiagnosticsCollector.flatten(safe)
    var measurements: [String: String] = [:]
    let names = ["cumulativeForegroundTime": "Foreground time", "cumulativeBackgroundTime": "Background time", "cumulativeCPUTime": "CPU time", "cumulativeLogicalWrites": "Disk writes", "cumulativeWifiDownload": "Wi-Fi downloaded", "cumulativeWifiUpload": "Wi-Fi uploaded"]
    for (key, label) in names {
      if let value = flattened.sorted(by: { $0.key < $1.key }).first(where: { $0.key.split(separator: ".").last.map(String.init) == key })?.value {
        measurements[label] = value
      }
    }
    return NativeDiagnosticReport(windowStart: windowStart ?? date(source["timeStampBegin"]), windowEnd: windowEnd ?? date(source["timeStampEnd"]), measurements: measurements, json: String(decoding: data, as: UTF8.self))
  }

  private static func date(_ value: Any?) -> Date? {
    guard let string = value as? String else { return nil }
    return JSONCodec.parseDate(string)
  }

  private static func sanitize(_ value: Any) -> Any? {
    if let number = value as? NSNumber { return number.doubleValue.isFinite ? number : nil }
    if let dictionary = value as? [String: Any] {
      let fields: Set<String> = [
        "exceptionType", "exceptionCode", "signal", "terminationReason", "callStackTree", "callStacks", "callStackRootFrames", "subFrames", "binaryUUID", "offsetIntoBinaryTextSegment", "address", "threadAttributed", "duration", "totalCPUTime", "totalSampledTime", "writesCaused",
        "cumulativeCPUTime", "cumulativeGPUTime", "cumulativeForegroundTime", "cumulativeBackgroundTime",
        "cumulativeHangTime", "cumulativeMemoryResourceLimitTime", "cumulativeLogicalWrites",
        "cumulativeCellularDownload", "cumulativeCellularUpload", "cumulativeWifiDownload", "cumulativeWifiUpload",
        "histogrammedTimeToFirstDraw", "histogrammedOptimizedTimeToFirstDraw", "histogrammedExtendedLaunch",
        "histogrammedApplicationResumeTime", "histogrammedAppLaunchTime", "histogrammedTimeToHang",
        "histogramNumBuckets", "histogramValue", "histogramBuckets", "bucketStart", "bucketEnd", "bucketCount",
        "averageSuspendedMemory", "peakMemoryUsage", "averagePixelLuminance", "cumulativeBestAccuracyTime",
        "cumulativeBestAccuracyForNavigationTime", "cumulativeNearestTenMetersAccuracyTime", "cumulativeHundredMetersAccuracyTime",
        "cumulativeKilometerAccuracyTime", "cumulativeThreeKilometersAccuracyTime", "averageMemory", "averageValue",
        "sampleCount", "standardDeviation", "foregroundExitData", "backgroundExitData",
        "cumulativeNormalAppExitCount", "cumulativeMemoryResourceLimitExitCount", "cumulativeAbnormalExitCount",
        "cumulativeBadAccessExitCount", "cumulativeIllegalInstructionExitCount", "cumulativeAppWatchdogExitCount",
        "cumulativeCPUResourceLimitExitCount", "cumulativeBackgroundTaskAssertionTimeoutExitCount",
        "cumulativeSuspendedWithLockedFileExitCount", "cumulativeMemoryPressureExitCount"
      ]
      return dictionary.filter { fields.contains($0.key) || $0.key.range(of: #"^bucket[0-9]+$"#, options: .regularExpression) != nil }.compactMapValues(sanitize)
    }
    if let array = value as? [Any] { return array.compactMap(sanitize) }
    if let string = value as? String {
      if date(string) != nil || UUID(uuidString: string) != nil { return string }
      if string.range(of: #"^(?:0x[0-9a-fA-F]+|SIG[A-Z0-9]+|EXC_[A-Z_]+)$"#, options: .regularExpression) != nil { return string }
      if string.range(of: #"^-?[0-9]+(?:\.[0-9]+)?(?:\s*(?:ms|s|sec|min|hr|h|B|kB|MB|GB|bytes|kilobytes|megabytes|percent|%|apl))?$"#, options: .regularExpression) != nil { return string }
    }
    return nil
  }
}
