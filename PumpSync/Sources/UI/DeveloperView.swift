import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DeveloperView: View {
  @Environment(AppServices.self) private var services
  @State private var copiedItem: String?

  private var history: SyncHistoryPresentation {
    SyncHistoryPresentation(metadata: services.syncMetadataStore.metadata,
      attempts: (services.syncCoordinator.attemptStore.active.map { [$0] } ?? []) + services.syncCoordinator.attemptStore.history)
  }

  var body: some View {
    PumpSyncScreen {
      GlassSection("Build") {
        GlassStatusRow(title: "Version", value: appVersion, systemImage: "number")
        GlassDivider()
        GlassStatusRow(title: "Installation ID", value: services.backendConfigurationStore.installationId,
          systemImage: "number.square", truncatesValue: true)
          .contextMenu { Button("Copy Installation ID", systemImage: "doc.on.doc", action: copyInstallationID) }
          .accessibilityIdentifier("InstallationIDRow")
          .accessibilityAction(named: "Copy", copyInstallationID)
        Button(copiedItem == "installation" ? "Installation ID Copied" : "Copy Installation ID", systemImage: "doc.on.doc", action: copyInstallationID)
          .buttonStyle(.bordered).tint(.primary).frame(minHeight: 44)
      }
      GlassSection("Current Account and Server") {
        GlassStatusRow(title: "Last attempt", value: formattedDate(history.lastAttempt), systemImage: "clock")
        GlassDivider()
        GlassStatusRow(title: "Last success", value: formattedDate(history.lastSuccess), systemImage: "checkmark.circle")
        GlassDivider()
        GlassStatusRow(title: "Returned", value: history.returned.map(String.init) ?? "Not recorded", systemImage: "tray.full")
        GlassDivider()
        GlassStatusRow(title: "Imported", value: history.imported.map(String.init) ?? "Not recorded", systemImage: "square.and.arrow.down")
        Text("Counts describe the last successful sync for this account and server. Token renewal does not reset history.")
          .font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText).padding(.vertical, 8)
        if let skipped = history.permissionSkipped, skipped > 0 {
          Text("\(skipped) records awaiting Health write access. Enable access and sync again while the records remain available from Tandem.")
        }
        if let reset = history.resetDescription { Text(reset).font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText) }
        if let error = services.syncMetadataStore.metadata.lastErrorMessage {
          GlassDivider()
          GlassStatusRow(title: "Last error", value: DiagnosticsRedactor.redacted(error), systemImage: "exclamationmark.triangle")
        }
      }
      GlassSection("Diagnostics") {
        NavigationLink { RealImportPreviewView(services: services) } label: {
          GlassNavigationRow("Inspect source data", subtitle: "View Tandem records without changing Apple Health", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.plain)
        .disabled(inspectUnavailableReason != nil)
        if let reason = inspectUnavailableReason {
          Text(reason).font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText).padding(.vertical, 8)
            .accessibilityIdentifier("InspectSourceDataUnavailableReason")
        }
        GlassDivider()
        ShareLink(item: SupportBundleBuilder.build(services: services)) {
          Label("Share Support Bundle", systemImage: "square.and.arrow.up").frame(minHeight: 44)
        }.buttonStyle(.bordered).tint(.primary)
        Text("Includes app/device versions, connection mode, current sync summary, up to 50 app events, 50 performance reports, and 20 completed attempts plus the active attempt. Excludes pump records and sign-in secrets. Review before sharing.")
          .font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText).padding(.vertical, 8)
      }
      GlassSection {
        logLink(.appEvents)
        GlassDivider()
        logLink(.devicePerformance)
      }
    }
    .navigationTitle("Developer")
  }

  private var inspectUnavailableReason: String? {
    if services.syncCoordinator.hasActiveSyncExecution { return "Wait for the current sync to finish before inspecting source data." }
    if !services.authService.isSignedIn { return "Connect to a service before inspecting source data." }
    if !services.credentialStore.hasValidatedCredentials { return "Save and validate your Tandem account before inspecting source data." }
    if services.authService.isReplacingConnection { return "Finish or cancel the connection change first." }
    return nil
  }

  private var appVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    return "\(version) (\(build))"
  }

  private func logLink(_ destination: DiagnosticsLogDestination) -> some View {
    NavigationLink { DiagnosticsLogView(destination: destination) } label: {
      GlassNavigationRow(destination.title, subtitle: destination == .devicePerformance && services.nativeDiagnosticsStore.storageMessage != nil ? "Temporarily unavailable" : "\(destination == .appEvents ? services.diagnosticsLogStore.entries.count : services.nativeDiagnosticsStore.entries.count) retained entries", systemImage: destination == .appEvents ? "list.bullet.rectangle" : "waveform.path.ecg")
    }.buttonStyle(.plain).accessibilityIdentifier(destination.rawValue + "LogLink")
  }

  private func copyInstallationID() {
    DiagnosticsClipboard.copy(services.backendConfigurationStore.installationId)
    showCopiedFeedback("installation")
  }

  private func showCopiedFeedback(_ item: String) {
    copiedItem = item
    UIAccessibility.post(notification: .announcement, argument: item == "installation" ? "Installation ID copied" : "All retained log entries copied")
    Task {
      try? await Task.sleep(for: .seconds(8))
      if copiedItem == item { copiedItem = nil }
    }
  }

  private func formattedDate(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .standard) ?? "Not recorded for this account and server" }
}

private struct DiagnosticsLogView: View {
  @Environment(AppServices.self) private var services
  let destination: DiagnosticsLogDestination
  @State private var logToClear: DiagnosticsLogDestination?
  @State private var copiedItem: String?

  var body: some View { diagnosticsLog(destination) }

  private func entryCount(_ destination: DiagnosticsLogDestination) -> Int {
    destination == .appEvents ? services.diagnosticsLogStore.entries.count : services.nativeDiagnosticsStore.entries.count
  }

  private func export(_ destination: DiagnosticsLogDestination) -> String {
    destination == .appEvents
      ? services.diagnosticsLogStore.entries.map(DiagnosticPresentation.export).joined(separator: "\n\n")
      : services.nativeDiagnosticsStore.entries.map(DiagnosticPresentation.export).joined(separator: "\n\n")
  }

  private func diagnosticsLog(_ destination: DiagnosticsLogDestination) -> some View {
    List {
      if destination == .devicePerformance, let message = services.nativeDiagnosticsStore.storageMessage {
        Text(message)
      }
      if entryCount(destination) == 0 && !(destination == .devicePerformance && services.nativeDiagnosticsStore.storageMessage != nil) {
        Text(destination == .appEvents ? "No app events recorded." : "No device performance diagnostics recorded.")
          .foregroundStyle(Color.pumpSyncSecondaryText).accessibilityIdentifier("EmptyDiagnosticsLog")
      } else if destination == .appEvents {
        ForEach(eventDates, id: \.self) { date in
          Section(date.formatted(date: .abbreviated, time: .omitted)) {
            ForEach(services.diagnosticsLogStore.entries.filter { Calendar.current.startOfDay(for: $0.timestamp) == date }) { entry in
              NavigationLink {
                DiagnosticDetailView(title: DiagnosticPresentation.title(for: entry), text: DiagnosticPresentation.export(entry))
              } label: {
                VStack(alignment: .leading, spacing: 6) {
                  Text(DiagnosticPresentation.title(for: entry)).font(.headline)
                  Text("\(entry.timestamp.formatted(date: .omitted, time: .standard)) · \(entry.severity.rawValue) · \(entry.source.rawValue)")
                    .font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText)
                  if let summary = DiagnosticPresentation.summary(for: entry) { Text(summary).font(.subheadline) }
                }.padding(.vertical, 4)
              }
            }
          }
        }
      } else {
        ForEach(services.nativeDiagnosticsStore.entries) { entry in
          NavigationLink {
            DiagnosticDetailView(title: entry.title, text: DiagnosticPresentation.export(entry), report: entry.report)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(entry.title).font(.headline)
              if let report = entry.report, let start = report.windowStart, let end = report.windowEnd {
                Text("\(start.formatted(date: .abbreviated, time: .standard)) – \(end.formatted(date: .abbreviated, time: .standard))")
              } else { Text("Report timestamp \(entry.timestamp.formatted(date: .abbreviated, time: .standard)) · Full window unavailable") }
              Text("\(entry.kind.rawValue) · App \(entry.appVersion) (\(entry.buildNumber))").font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText)
              Text(entry.report == nil ? "Legacy summary. Open details for retained fields." : entry.summary).font(.subheadline).lineLimit(3)
            }.padding(.vertical, 4)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(destination == .appEvents ? "App Event Log" : "Performance")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier(destination.rawValue + "LogScreen")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu("Log Actions", systemImage: "ellipsis") {
          Button(destination == .appEvents ? "Copy All App Events" : "Copy All Performance Reports", systemImage: "doc.on.doc") {
            DiagnosticsClipboard.copy(export(destination))
            showCopiedFeedback(destination.rawValue)
          }
          .accessibilityIdentifier("CopyDiagnosticsLog")
          .disabled(entryCount(destination) == 0)
          Button("Clear Logs", systemImage: "trash", role: .destructive) { logToClear = destination }
            .disabled(entryCount(destination) == 0 || (destination == .devicePerformance && services.nativeDiagnosticsStore.storageMessage != nil))
        }.accessibilityIdentifier("DiagnosticsLogActions")
      }
    }
    .safeAreaInset(edge: .bottom) {
      if copiedItem == destination.rawValue { Text("All \(destination == .appEvents ? "app events" : "performance reports") copied").padding().background(.bar).accessibilityIdentifier("DiagnosticsCopyFeedback") }
    }
    .alert("Clear Logs?", isPresented: Binding(get: { logToClear == destination }, set: { if !$0 { logToClear = nil } })) {
      Button("Clear Logs", role: .destructive) {
        if destination == .appEvents { services.diagnosticsLogStore.clear() }
        else { services.nativeDiagnosticsStore.clear() }
        logToClear = nil
      }
      Button("Cancel", role: .cancel) { logToClear = nil }
    } message: {
      Text("Clear all retained entries in \(destination.title)? Sync history, credentials, the other log, and Apple Health samples remain.")
    }
  }

  private var eventDates: [Date] {
    var seen = Set<Date>()
    return services.diagnosticsLogStore.entries.map { Calendar.current.startOfDay(for: $0.timestamp) }.filter { seen.insert($0).inserted }
  }

  private func showCopiedFeedback(_ item: String) {
    copiedItem = item
    UIAccessibility.post(notification: .announcement, argument: "All retained log entries copied")
  }
}

private enum DiagnosticsLogDestination: String, Identifiable {
  case appEvents, devicePerformance
  var id: String { rawValue }
  var title: String { self == .appEvents ? "App Event Log" : "Device Performance Diagnostics" }
}

enum DiagnosticsClipboard {
  @MainActor static func copy(_ string: String) {
    UIPasteboard.general.setItems([[UTType.plainText.identifier: DiagnosticsRedactor.redacted(string)]],
      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(2 * 60)])
  }
}

struct DiagnosticDetailView: View {
  let title: String
  let text: String
  var report: NativeDiagnosticReport? = nil
  @State private var copied = false

  var body: some View {
    PumpSyncScreen {
      if let report {
        GlassSection("Report Measurements") {
          if report.measurements.isEmpty { Text("No supported summary measurements in this report.") }
          ForEach(report.measurements.keys.sorted(), id: \.self) { key in
            LabeledContent(key, value: report.measurements[key] ?? "Unavailable").padding(.vertical, 6)
          }
          Text("Totals cover the reporting window, not a single sync. Histogram bucket boundaries are not averages or percentiles.")
            .font(.subheadline).foregroundStyle(Color.pumpSyncSecondaryText)
        }
      }
      Button(copied ? "Entry Copied" : "Copy Entry", systemImage: "doc.on.doc") {
        DiagnosticsClipboard.copy(text)
        copied = true
        UIAccessibility.post(notification: .announcement, argument: "Entry copied")
      }.buttonStyle(.bordered).tint(.primary).controlSize(.large)
      ShareLink(item: DiagnosticsRedactor.redacted(text)) { Label("Share Entry", systemImage: "square.and.arrow.up") }
        .buttonStyle(.bordered).tint(.primary).controlSize(.large)
      Text(DiagnosticsRedactor.redacted(text)).font(.body.monospaced()).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("DiagnosticRecordDetail")
    }
    .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
  }
}
