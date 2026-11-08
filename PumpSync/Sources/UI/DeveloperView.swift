import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DeveloperView: View {
  @Environment(AppServices.self) private var services
  @State private var copiedInstallationID = false

  private var history: SyncHistoryPresentation {
    SyncHistoryPresentation(metadata: services.syncMetadataStore.metadata,
      attempts: (services.syncCoordinator.attemptStore.active.map { [$0] } ?? []) + services.syncCoordinator.attemptStore.history)
  }

  var body: some View {
    Form {
      Section("Build") {
        LabeledContent("Version") {
          Text(appVersion).foregroundStyle(.primary)
        }
        LabeledContent("Installation ID") {
          Text(services.backendConfigurationStore.installationId)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("InstallationIDRow")
        .contextMenu { Button("Copy Installation ID", systemImage: "doc.on.doc", action: copyInstallationID) }
        .accessibilityAction(named: "Copy", copyInstallationID)
        Button(copiedInstallationID ? "Installation ID Copied" : "Copy Installation ID", systemImage: "doc.on.doc", action: copyInstallationID)
          .buttonStyle(.glass).controlSize(.regular)
      }
      .headerProminence(.increased)
      Section {
        LabeledContent("Last attempt") {
          Text(formattedDate(history.lastAttempt))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        LabeledContent("Last success") {
          Text(formattedDate(history.lastSuccess))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        LabeledContent("Records received") {
          Text(history.returned.map { $0.formatted() } ?? "Not recorded")
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        LabeledContent("Samples saved") {
          Text(history.imported.map { $0.formatted() } ?? "Not recorded")
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let skipped = history.permissionSkipped, skipped > 0 {
          Text("\(skipped) records awaiting Health write access. Enable access and sync again while the records remain available from Tandem.")
            .font(.body).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let reset = history.resetDescription {
          Text(reset).font(.body).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let error = services.syncMetadataStore.metadata.lastErrorMessage {
          LabeledContent("Last error") {
            Text(DiagnosticsRedactor.redacted(error))
              .foregroundStyle(.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Text("Counts describe the last successful sync for this account and server. Token renewal does not reset history.")
          .font(.body).foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text("Current Account and Server")
      }
      .headerProminence(.increased)
      Section {
        NavigationLink { RealImportPreviewView(services: services) } label: {
          Label("Inspect source data", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(inspectUnavailableReason != nil)
        if let reason = inspectUnavailableReason {
          Text(reason).font(.body).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("InspectSourceDataUnavailableReason")
        }
        logLink(.appEvents)
        logLink(.devicePerformance)
        ShareLink(item: SupportBundleBuilder.build(services: services)) {
          Label("Share Support Bundle", systemImage: "square.and.arrow.up")
        }.buttonStyle(.glass)
        Text("The support bundle includes app/device versions, connection mode, the current sync summary, up to 50 app events, 50 performance reports, and 20 completed attempts plus the active attempt. It excludes pump records and sign-in secrets. Review before sharing.")
          .font(.body).foregroundStyle(.primary)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text("Diagnostics")
      }
      .headerProminence(.increased)
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
      Label(destination.title, systemImage: destination.systemImage)
    }.accessibilityIdentifier(destination.rawValue + "LogLink")
  }

  private func copyInstallationID() {
    DiagnosticsClipboard.copy(services.backendConfigurationStore.installationId)
    copiedInstallationID = true
    UIAccessibility.post(notification: .announcement, argument: "Installation ID copied")
  }

  private func formattedDate(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "Not recorded for this account and server"
  }
}

enum DiagnosticsClipboard {
  @MainActor static func copy(_ string: String) {
    UIPasteboard.general.setItems([[UTType.plainText.identifier: DiagnosticsRedactor.redacted(string)]],
      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(2 * 60)])
  }
}
