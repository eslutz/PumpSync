import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DeveloperView: View {
  @Environment(AppServices.self) private var services
  @State private var copiedInstallationID = false

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
        Button(copiedInstallationID ? "Installation ID Copied" : "Copy Installation ID", systemImage: copiedInstallationID ? "checkmark" : "doc.on.doc", action: copyInstallationID)
          .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
          .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
      }
      .headerProminence(.increased)
      Section {
        NavigationLink { RealImportPreviewView(services: services) } label: {
          Label("Inspect source data", systemImage: "doc.text.magnifyingglass")
        }
        .disabled(inspectUnavailableReason != nil)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
        if let reason = inspectUnavailableReason {
          Text(reason).font(.body).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("InspectSourceDataUnavailableReason")
        }
        logLink(.appEvents)
        logLink(.devicePerformance)
        ShareLink(item: SupportBundleBuilder.build(services: services)) {
          Label("Share Support Bundle", systemImage: "square.and.arrow.up")
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
      } header: {
        Text("Diagnostics")
      } footer: {
        Text("Share app and sync diagnostics for troubleshooting. Pump records and sign-in details are excluded.")
          .font(.body)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .headerProminence(.increased)
    }
    .navigationTitle("Developer")
  }

  private var inspectUnavailableReason: String? {
    if services.syncCoordinator.hasActiveSyncExecution { return "Wait for the current sync to finish before inspecting source data." }
    if !services.authService.isSignedIn { return "Connect to a service before inspecting source data." }
    if !services.credentialStore.hasValidatedCredentials { return "Save and validate your Tandem account before inspecting source data." }
    if services.authService.isReplacingConnection { return "Finish connecting before inspecting source data." }
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
    }
    .accessibilityIdentifier(destination.rawValue + "LogLink")
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
  }

  private func copyInstallationID() {
    DiagnosticsClipboard.copy(services.backendConfigurationStore.installationId)
    copiedInstallationID = true
    UIAccessibility.post(notification: .announcement, argument: "Installation ID copied")
  }
}

enum DiagnosticsClipboard {
  @MainActor static func copy(_ string: String) {
    UIPasteboard.general.setItems([[UTType.plainText.identifier: DiagnosticsRedactor.redacted(string)]],
      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(2 * 60)])
  }
}
