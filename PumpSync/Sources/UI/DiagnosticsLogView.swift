import SwiftUI
import UIKit

struct DiagnosticsLogView: View {
  @Environment(AppServices.self) private var services
  let destination: DiagnosticsLogDestination
  @State private var confirmsClear = false
  @State private var copied = false

  private var count: Int {
    destination == .appEvents ? services.diagnosticsLogStore.entries.count : services.nativeDiagnosticsStore.entries.count
  }
  private var unavailable: String? {
    destination == .devicePerformance ? services.nativeDiagnosticsStore.storageMessage : nil
  }
  private var eventGroups: [DiagnosticEventGroup] {
    DiagnosticEventGroup.make(from: services.diagnosticsLogStore.entries)
  }
  private var eventDates: [Date] {
    var seen = Set<Date>()
    return eventGroups.map { Calendar.current.startOfDay(for: $0.timestamp) }.filter { seen.insert($0).inserted }
  }
  private var export: String {
    destination == .appEvents
      ? services.diagnosticsLogStore.entries.map(DiagnosticPresentation.export).joined(separator: "\n\n")
      : services.nativeDiagnosticsStore.entries.map(DiagnosticPresentation.export).joined(separator: "\n\n")
  }

  var body: some View {
    List {
      if let unavailable {
        ContentUnavailableView("Reports unavailable", systemImage: "exclamationmark.triangle", description: Text(unavailable))
      } else if count == 0 {
        ContentUnavailableView {
          Label(destination == .appEvents ? "No App Events" : "No Performance Reports", systemImage: destination.systemImage)
        } description: {
          Text(destination == .appEvents ? "App events will appear here as PumpSync runs." : "iOS delivers performance reports periodically. A new installation may not have one yet.")
        }
        .accessibilityIdentifier("EmptyDiagnosticsLog")
      } else if destination == .appEvents {
        ForEach(eventDates, id: \.self) { date in
          Section(date.formatted(date: .abbreviated, time: .omitted)) {
            ForEach(eventGroups.filter { Calendar.current.startOfDay(for: $0.timestamp) == date }) { group in
              NavigationLink { DiagnosticEventDetailView(group: group) } label: {
                DiagnosticEventRow(group: group)
              }
            }
          }
        }
      } else {
        ForEach(services.nativeDiagnosticsStore.entries) { entry in
          NavigationLink {
            DiagnosticDetailView(title: entry.title, text: DiagnosticPresentation.export(entry), report: entry.report,
                                 appVersion: "\(entry.appVersion) (\(entry.buildNumber))", timestamp: entry.timestamp)

          } label: {
            PerformanceReportRow(entry: entry)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(destination == .appEvents ? "App Event Log" : "Performance")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier(destination.rawValue + "LogScreen")
    .onChange(of: export) { _, _ in copied = false }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Log Actions", systemImage: "ellipsis") {
          Button(copied ? "Copied" : "Copy All", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyAll)
            .accessibilityLabel(copied
              ? (destination == .appEvents ? "All App Events Copied" : "All Performance Reports Copied")
              : (destination == .appEvents ? "Copy All App Events" : "Copy All Performance Reports"))
            .accessibilityValue(copied ? "Copied" : "")
            .accessibilityIdentifier("CopyDiagnosticsLog").disabled(count == 0)
          ShareLink(item: export) { Label("Share All", systemImage: "square.and.arrow.up") }.disabled(count == 0)
          Button(destination.clearTitle, systemImage: "trash", role: .destructive) { confirmsClear = true }
            .accessibilityIdentifier("ClearDiagnosticsLog").disabled(count == 0 || unavailable != nil)
        }.accessibilityIdentifier("DiagnosticsLogActions")
      }
    }
    .alert(destination.clearTitle + "?", isPresented: $confirmsClear) {
      Button(destination.clearTitle, role: .destructive, action: clear)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Clear all retained entries in \(destination.title)? Sync history, credentials, the other log, and Apple Health samples remain.")
    }
  }

  private func copyAll() {
    DiagnosticsClipboard.copy(export)
    copied = true
    UIAccessibility.post(notification: .announcement, argument: destination == .appEvents ? "All app events copied" : "All performance reports copied")
  }

  private func clear() {
    if destination == .appEvents { services.diagnosticsLogStore.clear() }
    else { services.nativeDiagnosticsStore.clear() }
    copied = false
  }
}

enum DiagnosticsLogDestination: String, Identifiable {
  case appEvents, devicePerformance
  var id: String { rawValue }
  var title: String { self == .appEvents ? "App Event Log" : "Device Performance Diagnostics" }
  var systemImage: String { self == .appEvents ? "list.bullet.rectangle" : "waveform.path.ecg" }
  var clearTitle: String { self == .appEvents ? "Clear App Events" : "Clear Performance Reports" }
}

private struct DiagnosticEventRow: View {
  let group: DiagnosticEventGroup

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(group.title).font(.headline)
      if let reason = group.latest.syncAttempt.flatMap(DiagnosticPresentation.reason) {
        Text(reason).font(.subheadline)
      } else if let summary = group.summary {
        Text(summary).font(.subheadline).lineLimit(2)
      }
      Text("\(group.timestamp.formatted(date: .omitted, time: .shortened)) · \(group.latest.source.rawValue)")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

private struct PerformanceReportRow: View {
  let entry: NativeDiagnosticEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.title).font(.headline)
      if let report = entry.report, let start = report.windowStart, let end = report.windowEnd {
        Text(start..<max(end, start.addingTimeInterval(1)), format: .interval.day().month(.abbreviated).hour().minute())
          .font(.subheadline)
      } else {
        Text(entry.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline)
      }
      Text(entry.report == nil ? "Legacy report · Full window unavailable" : entry.report?.measurements.isEmpty == true ? "No summary measurements" : "App \(entry.appVersion) (\(entry.buildNumber))")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}
