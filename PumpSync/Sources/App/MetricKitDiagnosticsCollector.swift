import Foundation
import MetricKit

/// Owns exactly one ingestion path. Retaining this object retains its listener;
/// releasing it unregisters the legacy subscriber or cancels both async tasks.
final class MetricKitDiagnosticsCollector {
  private let implementation: AnyObject?

  init(store: NativeDiagnosticsStore, bundle: Bundle = .main, isEnabled: Bool = true) {
    if !isEnabled {
      implementation = nil
    } else if #available(iOS 27.0, *) {
      implementation = AsyncMetricKitCollector(store: store)
      NativePerformance.metricCollectorStarted(modern: true)
    } else {
      implementation = LegacyMetricKitCollector(store: store)
      NativePerformance.metricCollectorStarted(modern: false)
    }
  }

  static func reportSummary(_ report: NativeDiagnosticReport) -> String {
    let keys = ["Foreground time", "CPU time", "Wi-Fi downloaded", "Disk writes"]
    let rows = keys.compactMap { key in report.measurements[key].map { "\(key): \($0)" } }
    return rows.isEmpty ? "No supported summary measurements in this report. Open details for retained fields." : rows.joined(separator: " · ")
  }

  static func flatten(_ value: Any, prefix: String = "") -> [String: String] {
    if let dictionary = value as? [String: Any] {
      return dictionary.reduce(into: [:]) { result, entry in
        let key = prefix.isEmpty ? entry.key : "\(prefix).\(entry.key)"
        result.merge(flatten(entry.value, prefix: key)) { existing, _ in existing }
      }
    }

    if let array = value as? [Any] {
      if array.isEmpty {
        return [:]
      }

      return array.enumerated().reduce(into: [:]) { result, entry in
        let key = "\(prefix)[\(entry.offset)]"
        result.merge(flatten(entry.element, prefix: key)) { existing, _ in existing }
      }
    }

    guard !prefix.isEmpty else {
      return [:]
    }

    if let number = value as? NSNumber {
      return [prefix: number.stringValue]
    }

    if let string = value as? String, !string.isEmpty {
      return [prefix: DiagnosticsLogStore.redacted(string)]
    }

    return [:]
  }

}

@available(iOS 27.0, *)
private final class AsyncMetricKitCollector {
  private let manager: MetricManager
  private let metricTask: Task<Void, Never>
  private let diagnosticTask: Task<Void, Never>

  init(store: NativeDiagnosticsStore) {
    let manager = MetricManager()
    self.manager = manager
    metricTask = Task.detached(priority: .utility) { [manager, store] in
      for await report in manager.metricReports {
        guard !Task.isCancelled else { return }
        let entry = NativePerformance.measure("Normalize MetricKit report") { MetricKitReportAdapter.performanceEntry(report) }
        guard !Task.isCancelled else { return }
        await store.record(entry)
      }
    }
    diagnosticTask = Task.detached(priority: .utility) { [manager, store] in
      for await report in manager.diagnosticReports {
        guard !Task.isCancelled else { return }
        let entry = NativePerformance.measure("Normalize MetricKit diagnostic") { MetricKitReportAdapter.diagnosticEntry(report) }
        guard !Task.isCancelled else { return }
        await store.record(entry)
      }
    }
  }

  deinit {
    metricTask.cancel()
    diagnosticTask.cancel()
  }
}

// Keeping the legacy types inside their supported OS range avoids deprecation
// warnings without disabling warnings or subscribing twice on newer systems.
@available(iOS, introduced: 13.0, obsoleted: 27.0)
private final class LegacyMetricKitCollector: NSObject, MXMetricManagerSubscriber {
  private let store: NativeDiagnosticsStore

  init(store: NativeDiagnosticsStore) {
    self.store = store
    super.init()
    MXMetricManager.shared.add(self)
  }

  deinit { MXMetricManager.shared.remove(self) }

  func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      let json = (try? JSONSerialization.jsonObject(with: payload.jsonRepresentation())) ?? [:]
      let report = NativeDiagnosticReport.make(from: json, windowStart: payload.timeStampBegin, windowEnd: payload.timeStampEnd)
      let entry = NativeDiagnosticEntry(
        timestamp: payload.timeStampEnd, kind: .performance, title: "Performance metrics",
        summary: MetricKitDiagnosticsCollector.reportSummary(report),
        appVersion: payload.latestApplicationVersion + (payload.includesMultipleApplicationVersions ? " (multiple versions)" : ""),
        buildNumber: payload.metaData?.applicationBuildVersion ?? "Not reported", report: report
      )
      Task { @MainActor [store] in store.record(entry) }
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      let json = (try? JSONSerialization.jsonObject(with: payload.jsonRepresentation())) as? [String: Any] ?? [:]
      let report = NativeDiagnosticReport.make(from: json, windowStart: payload.timeStampBegin, windowEnd: payload.timeStampEnd)
      let kind: NativeDiagnosticKind
      let title: String
      if !(payload.crashDiagnostics ?? []).isEmpty {
        kind = .crash; title = "Crash diagnostic"
      } else if !(payload.hangDiagnostics ?? []).isEmpty {
        kind = .hang; title = "Hang diagnostic"
      } else if !(payload.cpuExceptionDiagnostics ?? []).isEmpty {
        kind = .cpuException; title = "CPU exception diagnostic"
      } else {
        kind = .diagnostic; title = "Native diagnostic"
      }
      let entry = NativeDiagnosticEntry(
        timestamp: payload.timeStampEnd, kind: kind, title: title,
        summary: "MetricKit delivered a native diagnostic report. Open details for retained fields.",
        appVersion: "Not reported", buildNumber: "Not reported", report: report
      )
      Task { @MainActor [store] in store.record(entry) }
    }
  }
}
