import SwiftUI
import UIKit

struct DiagnosticDetailView: View {
  let title: String
  let text: String
  var report: NativeDiagnosticReport? = nil
  var appVersion: String? = nil
  var timestamp: Date? = nil
  @State private var copied = false

  var body: some View {
    Form {
      Section {
        if let start = report?.windowStart {
          LabeledContent("From") { Text(fullDate(start)).foregroundStyle(Color.primary) }
        }
        if let end = report?.windowEnd {
          LabeledContent("Through") { Text(fullDate(end)).foregroundStyle(Color.primary) }
        }
        if report?.windowStart == nil || report?.windowEnd == nil {
          Text("The full reporting window is unavailable.").foregroundStyle(.secondary)
          if let timestamp {
            LabeledContent("Reported") { Text(fullDate(timestamp)).foregroundStyle(Color.primary) }
          }
        }
        LabeledContent("Time zone") { Text(TimeZone.current.identifier).foregroundStyle(Color.primary) }
        if let appVersion {
          LabeledContent("App version") { Text(appVersion).foregroundStyle(Color.primary) }
        }
      } header: {
        Text(title).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
      }
      .headerProminence(.increased)
      Section {
        if let report, !report.measurements.isEmpty {
          ForEach(report.measurements.keys.sorted(), id: \.self) { key in
            LabeledContent(key) {
              Text(report.measurements[key] ?? "Unavailable").foregroundStyle(Color.primary)
            }
            .accessibilityIdentifier("PerformanceMeasurement-" + key)
          }
        } else {
          Text(report == nil ? "This legacy report contains a retained summary only." : "No supported summary measurements in this report.")
            .foregroundStyle(.secondary)
        }
        Text("Measurements cover the reporting period shown above and may include multiple syncs.")
          .font(.body)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text("Measurements")
      }
      .headerProminence(.increased)
      Section {
        DisclosureGroup("Report Data") {
          Text(DiagnosticsRedactor.redacted(text)).font(.body.monospaced()).textSelection(.enabled)
            .accessibilityIdentifier("DiagnosticRecordDetail")
        }
      }
    }
    .navigationTitle("Report").navigationBarTitleDisplayMode(.inline)
    .toolbar { DiagnosticExportActions(text: text, copied: $copied) }
  }

  private func fullDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .standard)
  }
}

struct DiagnosticEventDetailView: View {
  let group: DiagnosticEventGroup
  @State private var copied = false

  private var export: String { group.entries.map(DiagnosticPresentation.export).joined(separator: "\n\n") }

  var body: some View {
    Form {
      Section("Summary") {
        Text(group.title).font(.headline)
        if let attempt = group.latest.syncAttempt {
          if let reason = DiagnosticPresentation.reason(for: attempt) { Text(reason) }
          if let received = attempt.returnedCount {
            LabeledContent("Records received") { Text(received.formatted()).foregroundStyle(Color.primary) }
          }
          if let saved = attempt.importedCount {
            LabeledContent("Samples saved") { Text(saved.formatted()).foregroundStyle(Color.primary) }
          }
          if let skipped = attempt.permissionSkippedCount, skipped > 0 {
            LabeledContent("Awaiting Health access") { Text(skipped.formatted()).foregroundStyle(Color.primary) }
          }
          LabeledContent("Started") { Text(fullDate(attempt.startedAt)).foregroundStyle(Color.primary) }
          if let completed = attempt.completedAt {
            LabeledContent("Completed") { Text(fullDate(completed)).foregroundStyle(Color.primary) }
          }
          if let duration = attempt.durationSeconds {
            LabeledContent("Duration") {
              Text(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                .foregroundStyle(Color.primary)
            }
          }
        } else if let preview = DiagnosticPresentation.importPreview(for: group.latest) {
          LabeledContent("Status") {
            Text(DiagnosticPresentation.previewStatus(preview.status)).foregroundStyle(Color.primary)
          }
          if let source = preview.source {
            LabeledContent("Source") {
              Text(DiagnosticPresentation.previewSource(source)).foregroundStyle(Color.primary)
            }
          }
          if let count = preview.recordCount {
            LabeledContent("Records available") { Text(count.formatted()).foregroundStyle(Color.primary) }
          }
        } else if let summary = DiagnosticPresentation.summary(for: group.latest) {
          Text(summary)
        }
        LabeledContent("Recorded") { Text(fullDate(group.timestamp)).foregroundStyle(Color.primary) }
        LabeledContent("Time zone") { Text(TimeZone.current.identifier).foregroundStyle(Color.primary) }
      }
      if group.entries.count > 1 {
        Section {
          DisclosureGroup("Recorded Stages") {
            ForEach(group.entries.reversed()) { entry in
              VStack(alignment: .leading, spacing: 4) {
                Text(DiagnosticPresentation.title(for: entry))
                if let checkpoint = entry.syncAttempt?.importCheckpoint { Text(checkpoint.rawValue).font(.caption) }
                Text(entry.timestamp, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        } footer: {
          Text("This timeline includes retained snapshots only; older stages may no longer be available.")
            .font(.body)
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Section {
        DisclosureGroup("Log Details") {
          Text(export).font(.body.monospaced()).textSelection(.enabled).accessibilityIdentifier("DiagnosticRecordDetail")
        }
      }
    }
    .navigationTitle("App Event").navigationBarTitleDisplayMode(.inline)
    .toolbar { DiagnosticExportActions(text: export, copied: $copied) }
  }

  private func fullDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .standard)
  }
}

private struct DiagnosticExportActions: ToolbarContent {
  let text: String
  @Binding var copied: Bool

  var body: some ToolbarContent {
    if #available(iOS 27.0, *) {
      ToolbarItem(placement: .topBarTrailing) { copyAction }
        .visibilityPriority(.low)
      ToolbarItem(placement: .topBarTrailing) { shareAction }
        .visibilityPriority(.low)
    } else {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Export Actions", systemImage: "ellipsis") {
          copyAction
          shareAction
        }
        .accessibilityIdentifier("DiagnosticExportActions")
      }
    }
  }

  private var copyAction: some View {
    Button(copied ? "Entry Copied" : "Copy Entry", systemImage: copied ? "checkmark" : "doc.on.doc") {
      DiagnosticsClipboard.copy(text)
      copied = true
      UIAccessibility.post(notification: .announcement, argument: "Entry copied")
    }
    .accessibilityIdentifier("CopyDiagnosticEntry")
    .accessibilityValue(copied ? "Copied" : "")
  }

  private var shareAction: some View {
    ShareLink(item: DiagnosticsRedactor.redacted(text)) { Label("Share Entry", systemImage: "square.and.arrow.up") }
      .accessibilityIdentifier("ShareDiagnosticEntry")
  }
}

#Preview("Performance measurements") {
  let report = NativeDiagnosticReport.make(from: ["cpuMetrics": ["cumulativeCPUTime": "1 sec"],
    "applicationTimeMetrics": ["cumulativeForegroundTime": "15 sec"]],
    windowStart: Date().addingTimeInterval(-86_400), windowEnd: Date())
  NavigationStack { DiagnosticDetailView(title: "Performance metrics", text: report.json, report: report, appVersion: "1.0 (54)") }
}

#Preview("Legacy performance report") {
  NavigationStack { DiagnosticDetailView(title: "Performance metrics", text: "Legacy report summary", timestamp: Date()) }
}

#Preview("Empty performance measurements") {
  let report = NativeDiagnosticReport.make(from: [:], windowStart: Date().addingTimeInterval(-86_400), windowEnd: Date())
  NavigationStack { DiagnosticDetailView(title: "Performance metrics", text: report.json, report: report) }
}
