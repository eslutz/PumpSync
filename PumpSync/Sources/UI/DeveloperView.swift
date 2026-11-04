import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DeveloperView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var logToClear: DiagnosticsLogDestination?
  @State private var copiedItem: CopiedDiagnosticsItem?

  var body: some View {
    PumpSyncScreen {
      GlassSection("Build") {
        GlassStatusRow(title: "Version", value: appVersion, systemImage: "number")
        GlassDivider()
        GlassStatusRow(
          title: "Installation ID",
          value: services.backendConfigurationStore.installationId,
          systemImage: copiedItem == .installationId ? "checkmark.circle" : "number.square"
        )
        .contentShape(Rectangle())
        .contextMenu {
          Button("Copy", systemImage: "doc.on.doc", action: copyInstallationID)
        }
        .accessibilityIdentifier("InstallationIDRow")
        .accessibilityHint("Touch and hold to copy the installation ID")
        .accessibilityAction(named: "Copy", copyInstallationID)
      }

      GlassSection("Sync") {
        GlassStatusRow(title: "Last attempt", value: formattedDate(services.syncMetadataStore.metadata.lastAttemptAt), systemImage: "clock")
        GlassDivider()
        GlassStatusRow(title: "Last success", value: formattedDate(services.syncMetadataStore.metadata.lastSuccessfulSyncAt), systemImage: "checkmark.circle")
        GlassDivider()
        GlassStatusRow(title: "Returned", value: "\(services.syncMetadataStore.metadata.lastSampleCount)", systemImage: "tray.full")
        GlassDivider()
        GlassStatusRow(title: "Imported", value: "\(services.syncMetadataStore.metadata.lastImportedCount)", systemImage: "square.and.arrow.down")

        if let lastError = services.syncMetadataStore.metadata.lastErrorMessage {
          GlassDivider()
          GlassStatusRow(title: "Last error", value: DiagnosticsLogStore.redacted(lastError), systemImage: "exclamationmark.triangle")
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        diagnosticsSectionHeading("Diagnostics")

        GlassSection {
          NavigationLink {
            RealImportPreviewView(services: services)
          } label: {
            GlassNavigationRow("Inspect source data", subtitle: "View Tandem records without changing Apple Health", systemImage: "doc.text.magnifyingglass")
          }
          .buttonStyle(.plain)
          .disabled(!services.authService.isSignedIn || !services.credentialStore.hasValidatedCredentials || services.syncCoordinator.isSyncing)
          .accessibilityHint("Inspects records from your connected pump account without importing them")
          GlassDivider()
            .padding(.vertical, 8)

          ShareLink(item: supportBundleText) {
            GlassPrimaryLabel(title: "Share Support Bundle", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(GroupedRowActionButtonStyle())
          .foregroundStyle(.tint)
        }

        GlassSection {
          logLink(.appEvents)
          GlassDivider()
          logLink(.devicePerformance)
        }
      }
    }
    .navigationTitle("Developer")
  }

  private var appVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    return "\(version) (\(build))"
  }

  private var diagnosticsText: String {
    services.diagnosticsLogStore.entries
      .map { entry in
        [
          entry.timestamp.formatted(date: .abbreviated, time: .standard),
          entry.source.rawValue,
          entry.severity.rawValue,
          entry.title,
          entry.message ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " | ")
      }
      .joined(separator: "\n")
  }

  private var nativeDiagnosticsText: String {
    services.nativeDiagnosticsStore.entries
      .map { entry in
        [
          entry.timestamp.formatted(date: .abbreviated, time: .standard),
          entry.kind.rawValue,
          entry.title,
          "App \(entry.appVersion) (\(entry.buildNumber))",
          entry.summary.replacingOccurrences(of: "\n", with: " ; ")
        ]
        .joined(separator: " | ")
      }
      .joined(separator: "\n")
  }

  private var supportBundleText: String {
    SupportBundleBuilder.build(services: services)
  }

  private func logLink(_ destination: DiagnosticsLogDestination) -> some View {
    NavigationLink {
      diagnosticsLog(destination)
    } label: {
      GlassNavigationRow(
        destination.title,
        subtitle: logSummary(destination),
        systemImage: destination == .appEvents ? "list.bullet.rectangle" : "waveform.path.ecg"
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(destination.rawValue + "LogLink")
  }

  private func logSummary(_ destination: DiagnosticsLogDestination) -> String {
    let count = destination == .appEvents
      ? services.diagnosticsLogStore.entries.count : services.nativeDiagnosticsStore.entries.count
    let latest = destination == .appEvents
      ? services.diagnosticsLogStore.entries.map(\.timestamp).max()
      : services.nativeDiagnosticsStore.entries.map(\.timestamp).max()
    guard let latest else { return "No entries recorded" }
    let countLabel = count == 1 ? "1 entry" : "\(count) entries"
    return "\(countLabel) · Latest \(formattedDate(latest))"
  }

  private func hasEntries(_ destination: DiagnosticsLogDestination) -> Bool {
    destination == .appEvents
      ? !services.diagnosticsLogStore.entries.isEmpty : !services.nativeDiagnosticsStore.entries.isEmpty
  }

  private func diagnosticsLog(_ destination: DiagnosticsLogDestination) -> some View {
    List {
      Section {
        if !hasEntries(destination) {
          Text(destination == .appEvents ? "No app events recorded." : "No device performance diagnostics recorded.")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("EmptyDiagnosticsLog")
        } else if destination == .appEvents {
          ForEach(services.diagnosticsLogStore.entries) { entry in
            diagnosticRow(entry)
          }
        } else {
          ForEach(services.nativeDiagnosticsStore.entries) { entry in
            nativeDiagnosticRow(entry)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(destination == .appEvents ? "App Event Log" : "Performance")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityIdentifier(destination.rawValue + "LogScreen")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          copyToClipboard(destination == .appEvents ? diagnosticsText : nativeDiagnosticsText)
          showCopiedFeedback(for: destination == .appEvents ? .appEventLog : .devicePerformanceDiagnostics)
          UIAccessibility.post(notification: .announcement, argument: "Logs copied")
        } label: {
          Label(copiedItem == (destination == .appEvents ? .appEventLog : .devicePerformanceDiagnostics)
                ? "Copied" : "Copy Logs", systemImage: "doc.on.doc")
        }
        .accessibilityLabel("Copy \(destination.title)")
        .accessibilityIdentifier("CopyDiagnosticsLog")
        .disabled(!hasEntries(destination))

        Menu("Log Actions", systemImage: "ellipsis") {
          Button("Clear Logs", systemImage: "trash", role: .destructive) {
            logToClear = destination
          }
          .disabled(!hasEntries(destination))
        }
        .accessibilityIdentifier("DiagnosticsLogActions")
      }
    }
    .alert("Clear Logs?", isPresented: Binding(
      get: { logToClear == destination },
      set: { if !$0 { logToClear = nil } }
    )) {
      Button("Clear Logs", role: .destructive) {
        if destination == .appEvents {
          services.diagnosticsLogStore.clear()
        } else {
          services.nativeDiagnosticsStore.clear()
        }
        logToClear = nil
      }
      Button("Cancel", role: .cancel) { logToClear = nil }
    } message: {
      Text("Clear all entries in \(destination.title)?")
    }
  }

  /// Diagnostics and the installation ID are only meant for a one-off paste
  /// into a support message, not indefinite storage — .localOnly keeps them
  /// out of Universal Clipboard sync to other devices, and expirationDate
  /// clears the pasteboard entry automatically rather than leaving it
  /// sitting there until overwritten.
  private func copyToClipboard(_ string: String) {
    UIPasteboard.general.setItems(
      [[UTType.plainText.identifier: string]],
      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(2 * 60)]
    )
  }

  private func copyInstallationID() {
    copyToClipboard(services.backendConfigurationStore.installationId)
    showCopiedFeedback(for: .installationId)
    UIAccessibility.post(notification: .announcement, argument: "Installation ID copied")
  }

  private func showCopiedFeedback(for item: CopiedDiagnosticsItem) {
    copiedItem = item
    Task {
      try? await Task.sleep(for: .seconds(1.8))
      if copiedItem == item {
        copiedItem = nil
      }
    }
  }

  private func diagnosticsSectionHeading(_ title: String) -> some View {
    Text(title)
      .font(.headline)
      .accessibilityAddTraits(.isHeader)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
  }

  private func diagnosticRow(_ entry: DiagnosticEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      diagnosticsMetadataLayout {
        Text(entry.source.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Text(entry.severity.rawValue)
          .font(.caption)
          .foregroundStyle(severityColor(entry.severity))

        if !dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: 0)
        }

        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Text(entry.title)
        .font(.subheadline.weight(.semibold))

      if let message = entry.message {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(entry.title)
    .accessibilityValue([
      entry.source.rawValue,
      entry.severity.rawValue,
      entry.timestamp.formatted(date: .abbreviated, time: .standard),
      entry.message ?? ""
    ].filter { !$0.isEmpty }.joined(separator: ", "))
  }

  private func nativeDiagnosticRow(_ entry: NativeDiagnosticEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      diagnosticsMetadataLayout {
        Text(entry.kind.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Text("App \(entry.appVersion) (\(entry.buildNumber))")
          .font(.caption)
          .foregroundStyle(.tertiary)

        if !dynamicTypeSize.isAccessibilitySize {
          Spacer(minLength: 0)
        }

        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Text(entry.title)
        .font(.subheadline.weight(.semibold))

      Text(entry.summary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(entry.title)
    .accessibilityValue([
      entry.kind.rawValue,
      "App \(entry.appVersion) build \(entry.buildNumber)",
      entry.timestamp.formatted(date: .abbreviated, time: .standard),
      entry.summary
    ].joined(separator: ", "))
  }

  private var diagnosticsMetadataLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(spacing: 8))
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  private func severityColor(_ severity: DiagnosticSeverity) -> Color {
    switch severity {
    case .info:
      return .secondary
    case .warning:
      return .orange
    case .error:
      return .red
    }
  }
}

private enum CopiedDiagnosticsItem {
  case installationId
  case appEventLog
  case devicePerformanceDiagnostics
}

private enum DiagnosticsLogDestination: String, Identifiable {
  case appEvents, devicePerformance
  var id: String { rawValue }
  var title: String {
    switch self {
    case .appEvents: "App Event Log"
    case .devicePerformance: "Device Performance Diagnostics"
    }
  }
}
