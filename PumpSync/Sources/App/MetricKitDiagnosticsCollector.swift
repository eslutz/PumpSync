import Foundation
import MetricKit

final class MetricKitDiagnosticsCollector: NSObject, MXMetricManagerSubscriber {
  private let store: NativeDiagnosticsStore
  private let bundleInfo: AppBundleInfo
  private let isEnabled: Bool

  init(store: NativeDiagnosticsStore, bundle: Bundle = .main, isEnabled: Bool = true) {
    self.store = store
    self.bundleInfo = AppBundleInfo(bundle: bundle)
    self.isEnabled = isEnabled
    super.init()

    if isEnabled {
      MXMetricManager.shared.add(self)
    }
  }

  deinit {
    if isEnabled {
      MXMetricManager.shared.remove(self)
    }
  }

  func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      let entry = makeEntry(
        kind: .performance,
        title: "Performance metrics",
        timestamp: payload.timeStampEnd,
        summary: Self.summary(from: payload, preferredKeys: Self.performanceSummaryKeys)
      )
      Task { @MainActor in
        store.record(entry)
      }
    }
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      let entry = makeEntry(
        kind: .crash,
        title: Self.crashTitle(from: payload),
        timestamp: payload.timeStampEnd,
        summary: Self.summary(
          from: payload,
          preferredKeys: Self.crashSummaryKeys,
          fallback: "MetricKit delivered a native diagnostic payload."
        )
      )
      Task { @MainActor in
        store.record(entry)
      }
    }
  }

  private func makeEntry(
    kind: NativeDiagnosticKind,
    title: String,
    timestamp: Date,
    summary: String
  ) -> NativeDiagnosticEntry {
    NativeDiagnosticEntry(
      timestamp: timestamp,
      kind: kind,
      title: title,
      summary: summary,
      appVersion: bundleInfo.version,
      buildNumber: bundleInfo.build
    )
  }
}

extension MetricKitDiagnosticsCollector {
  static let performanceSummaryKeys = [
    "timeStampBegin",
    "timeStampEnd",
    "cumulativeForegroundTime",
    "cumulativeBackgroundTime",
    "cumulativeHangTime",
    "histogrammedTimeToFirstDraw",
    "histogrammedApplicationResumeTime",
    "cumulativeCPUTime",
    "cumulativeMemoryResourceLimitTime",
    "cumulativeLogicalWrites",
    "cumulativeCellularDownload",
    "cumulativeWifiDownload"
  ]

  static let crashSummaryKeys = [
    "timeStampBegin",
    "timeStampEnd",
    "exceptionType",
    "exceptionCode",
    "signal",
    "terminationReason"
  ]

  static func summary(
    from payload: NSObject,
    preferredKeys: [String],
    fallback: String? = nil
  ) -> String {
    let json = metricKitJSON(from: payload)
    let flattened = flatten(json)
    var lines: [String] = []

    for key in preferredKeys {
      let matches = flattened
        .filter { $0.key.localizedCaseInsensitiveContains(key) }
        .sorted { $0.key < $1.key }
        .prefix(3)

      for match in matches {
        lines.append("\(shortKey(match.key)): \(match.value)")
      }
    }

    if lines.isEmpty {
      if let fallback {
        return fallback
      }

      lines = flattened
        .sorted { $0.key < $1.key }
        .prefix(8)
        .map { "\(shortKey($0.key)): \($0.value)" }
    }

    return lines.isEmpty ? "MetricKit delivered a diagnostic payload." : lines.joined(separator: "\n")
  }

  static func crashTitle(from payload: NSObject) -> String {
    let json = metricKitJSON(from: payload)
    let flattened = flatten(json)

    if flattened.keys.contains(where: { $0.localizedCaseInsensitiveContains("crashDiagnostics") }) {
      return "Crash diagnostic"
    }

    if flattened.keys.contains(where: { $0.localizedCaseInsensitiveContains("hangDiagnostics") }) {
      return "Hang diagnostic"
    }

    if flattened.keys.contains(where: { $0.localizedCaseInsensitiveContains("cpuExceptionDiagnostics") }) {
      return "CPU exception diagnostic"
    }

    return "Native diagnostic"
  }

  static func metricKitJSON(from payload: NSObject) -> Any {
    let data: Data?
    if let metricPayload = payload as? MXMetricPayload {
      data = metricPayload.jsonRepresentation()
    } else if let diagnosticPayload = payload as? MXDiagnosticPayload {
      data = diagnosticPayload.jsonRepresentation()
    } else {
      data = nil
    }

    guard
      let data,
      let object = try? JSONSerialization.jsonObject(with: data)
    else {
      return [:]
    }

    return object
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

  private static func shortKey(_ key: String) -> String {
    key
      .split(separator: ".")
      .suffix(3)
      .joined(separator: ".")
  }
}
