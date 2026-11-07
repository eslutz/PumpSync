import Foundation

enum DiagnosticPresentation {
  static func title(for entry: DiagnosticEntry) -> String {
    guard let attempt = entry.syncAttempt else { return DiagnosticsRedactor.redacted(entry.title) }
    let trigger: String = switch attempt.trigger {
    case .manual: "Manual"
    case .appOpen: "App-open"
    case .background: "Background"
    }
    let outcome: String = switch attempt.outcome {
    case .completed: "completed"
    case .failed: "failed"
    case .blocked: "needs attention"
    case .deferred: "deferred"
    case .skipped: "already up to date"
    case .canceled: "canceled"
    case .contextReplaced: "stopped after settings changed"
    case .interrupted: "interrupted"
    case nil: attempt.stage.rawValue
    }
    return "\(trigger) sync \(outcome)"
  }

  static func summary(for entry: DiagnosticEntry) -> String? {
    guard let attempt = entry.syncAttempt else {
      return entry.message == nil ? nil : "Open details for the diagnostic record."
    }
    guard let returned = attempt.returnedCount else { return "Counts not recorded for this stage." }
    var parts = ["\(returned) returned", attempt.importedCount.map { "\($0) imported" } ?? "Import count unavailable"]
    if let skipped = attempt.permissionSkippedCount, skipped > 0 { parts.append("\(skipped) awaiting Health access") }
    return parts.joined(separator: " · ")
  }

  static func exactTime(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func export(_ entry: DiagnosticEntry) -> String {
    DiagnosticsRedactor.redacted([
      exactTime(entry.timestamp), entry.source.rawValue, entry.severity.rawValue,
      title(for: entry), entry.title, entry.message ?? "",
      entry.syncAttempt.map(SyncAttemptStore.description) ?? ""
    ].filter { !$0.isEmpty }.joined(separator: " | "))
  }

  static func export(_ entry: NativeDiagnosticEntry) -> String {
    let report = entry.report.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.json.utf8))).map { NativeDiagnosticReport.make(from: $0) } }
    return DiagnosticsRedactor.redacted([
      exactTime(entry.timestamp), entry.kind.rawValue, entry.title,
      "App \(entry.appVersion) (\(entry.buildNumber))", entry.summary,
      report?.json ?? "Legacy summary only; original payload was not retained."
    ].joined(separator: "\n"))
  }
}

struct SyncHistoryPresentation {
  let lastAttempt: Date?
  let lastSuccess: Date?
  let returned: Int?
  let imported: Int?
  let permissionSkipped: Int?
  let resetDescription: String?

  var countsSummary: String? {
    guard lastSuccess != nil else { return nil }
    var parts = [imported.map { "\($0) imported" } ?? "Import count unavailable",
                 returned.map { "\($0) returned" } ?? "Returned count unavailable"]
    if let permissionSkipped, permissionSkipped > 0 { parts.append("\(permissionSkipped) awaiting Health access") }
    return parts.joined(separator: " · ")
  }

  init(metadata: SyncMetadata, attempts: [SyncAttempt]) {
    lastAttempt = attempts.first { $0.historyScopeID == metadata.historyScopeID }?.startedAt ?? metadata.lastAttemptAt
    lastSuccess = metadata.lastSuccessfulSyncAt
    returned = lastSuccess == nil ? nil : metadata.lastSampleCount
    imported = lastSuccess == nil ? nil : metadata.lastImportedCount
    permissionSkipped = metadata.lastPermissionSkippedCount
    resetDescription = metadata.cursorResetReason.map {
      switch $0 {
      case .legacyUnbound: "Earlier history could not be bound to this account and server."
      case .accountChanged: "History restarted when the Tandem account changed."
      case .backendChanged: "History restarted when the server changed."
      case .credentialsDeleted: "History restarted when saved credentials were removed."
      }
    }
  }
}

/// Retain supported numeric fields and validated metadata, never arbitrary strings
/// or full crash payloads. JSON is lossless for these allowlisted fields only.
struct NativeDiagnosticReport: Codable, Equatable {
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
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
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
      if string.range(of: #"^-?[0-9]+(?:\.[0-9]+)?(?:\s*(?:ms|s|sec|min|hr|h|B|kB|MB|GB|bytes|kilobytes|megabytes|percent|%))?$"#, options: .regularExpression) != nil { return string }
    }
    return nil
  }
}
