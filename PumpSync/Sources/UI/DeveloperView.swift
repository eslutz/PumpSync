import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DeveloperView: View {
  @Environment(AppServices.self) private var services
  @State private var expandedLog: DiagnosticsLogDestination?
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
          VStack(alignment: .leading, spacing: 18) {
            logHeading(.appEvents)
            appEventLogContent()
          }
        }

        GlassSection {
          VStack(alignment: .leading, spacing: 18) {
            logHeading(.devicePerformance)
            devicePerformanceDiagnosticsContent()
          }
        }
      }
    }
    .navigationTitle("Developer")
    .fullScreenCover(item: $expandedLog) { destination in
      DiagnosticsLogFullScreen(title: destination.title) {
        switch destination {
        case .appEvents: appEventLogContent(expanded: true)
        case .devicePerformance: devicePerformanceDiagnosticsContent(expanded: true)
        }
      }
    }
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

  @ViewBuilder
  private func appEventLogContent(expanded: Bool = false) -> some View {
    if services.diagnosticsLogStore.entries.isEmpty {
      Text("No app events recorded.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    } else {
      logViewport(expanded: expanded, identifier: "AppEventLogScroll") {
        ForEach(services.diagnosticsLogStore.entries) { entry in
          diagnosticRow(entry)
        }
      }

      GlassDivider()

      diagnosticsActions(
        copyTitle: "Copy App Event Log",
        clearTitle: "Clear App Event Log",
        copiedItem: .appEventLog,
        copy: { diagnosticsText },
        clear: { services.diagnosticsLogStore.clear() }
      )
    }
  }

  @ViewBuilder
  private func devicePerformanceDiagnosticsContent(expanded: Bool = false) -> some View {
    if services.nativeDiagnosticsStore.entries.isEmpty {
      Text("No device performance diagnostics recorded.")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    } else {
      logViewport(expanded: expanded, identifier: "DevicePerformanceLogScroll") {
        ForEach(services.nativeDiagnosticsStore.entries) { entry in
          nativeDiagnosticRow(entry)
        }
      }

      GlassDivider()

      diagnosticsActions(
        copyTitle: "Copy Device Performance Diagnostics",
        clearTitle: "Clear Device Performance Diagnostics",
        copiedItem: .devicePerformanceDiagnostics,
        copy: { nativeDiagnosticsText },
        clear: { services.nativeDiagnosticsStore.clear() }
      )
    }
  }

  private func logHeading(_ destination: DiagnosticsLogDestination) -> some View {
    HStack(alignment: .top, spacing: 12) {
      diagnosticsSubheading(destination.title)
        .padding(.top, 12)
      Button {
        expandedLog = destination
      } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .frame(width: 48, height: 48)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Open \(destination.title) Full Screen")
      .accessibilityIdentifier(destination.rawValue + "FullScreen")
    }
  }

  private func logViewport<Content: View>(expanded: Bool, identifier: String, @ViewBuilder content: () -> Content) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12, content: content)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.visible)
    .frame(height: expanded ? nil : 280)
    .frame(maxHeight: expanded ? .infinity : nil)
    .accessibilityIdentifier(identifier)
  }

  private func diagnosticsActions(
    copyTitle: String,
    clearTitle: String,
    copiedItem item: CopiedDiagnosticsItem,
    copy: @escaping () -> String,
    clear: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        copyToClipboard(copy())
        showCopiedFeedback(for: item)
      } label: {
        Label(copiedItem == item ? "Copied" : copyTitle, systemImage: copiedItem == item ? "checkmark.circle" : "doc.on.doc")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.tint)
      .accessibilityHint("Copies diagnostics to the clipboard")

      Button(role: .destructive) {
        clear()
      } label: {
        Label(clearTitle, systemImage: "trash")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.red)
    }
    .padding(.top, 6)
    .padding(.bottom, 2)
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

  private func diagnosticsSubheading(_ title: String) -> some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func diagnosticsSectionHeading(_ title: String) -> some View {
    Text(title)
      .font(.headline)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
  }

  private func diagnosticRow(_ entry: DiagnosticEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(entry.source.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Text(entry.severity.rawValue)
          .font(.caption)
          .foregroundStyle(severityColor(entry.severity))

        Spacer(minLength: 0)

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
      entry.message ?? ""
    ].filter { !$0.isEmpty }.joined(separator: ", "))
  }

  private func nativeDiagnosticRow(_ entry: NativeDiagnosticEntry) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Text(entry.kind.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Text("App \(entry.appVersion) (\(entry.buildNumber))")
          .font(.caption)
          .foregroundStyle(.tertiary)

        Spacer(minLength: 0)

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
      entry.summary
    ].joined(separator: ", "))
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

private struct DiagnosticsLogFullScreen<Content: View>: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        content()
      }
      .padding(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color(.systemGroupedBackground))
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Close", systemImage: "xmark") { dismiss() }
            .accessibilityIdentifier("CloseDiagnosticsLog")
        }
      }
    }
  }
}
