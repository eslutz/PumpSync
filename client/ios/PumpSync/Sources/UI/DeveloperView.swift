import SwiftUI
import UIKit

struct DeveloperView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      GlassSection("Build") {
        GlassStatusRow(title: "Version", value: appVersion, systemImage: "number")
        GlassDivider()
        GlassStatusRow(title: "Bundle", value: bundleIdentifier, systemImage: "app.badge")
        GlassDivider()
        GlassStatusRow(title: "API", value: services.apiClient.baseURL.absoluteString, systemImage: "network")
      }

      GlassSection("State") {
        GlassStatusRow(title: "Backend", value: services.authService.isSignedIn ? "Connected" : "Not connected", systemImage: "network")
        GlassDivider()
        GlassStatusRow(title: "Mode", value: services.backendConfigurationStore.mode.title, systemImage: "server.rack")
        GlassDivider()
        GlassStatusRow(title: "Tandem", value: tandemCredentialStatus, systemImage: "key")
        GlassDivider()
        GlassStatusRow(title: "Health", value: healthWriteStatus, systemImage: "heart")
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

      GlassSection("Background") {
        GlassStatusRow(title: "Task identifier", value: AppConstants.backgroundTaskIdentifier, systemImage: "calendar.badge.clock")
      }

      GlassSection("Diagnostics") {
        if services.diagnosticsLogStore.entries.isEmpty {
          Text("No diagnostics recorded.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(services.diagnosticsLogStore.entries.prefix(50)) { entry in
              diagnosticRow(entry)
            }
          }

          GlassDivider()

          HStack {
            Button {
              UIPasteboard.general.string = diagnosticsText
            } label: {
              Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Button(role: .destructive) {
              services.diagnosticsLogStore.clear()
            } label: {
              Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.plain)
          }
          .padding(.top, 12)
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

  private var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? "Unknown"
  }

  private var tandemCredentialStatus: String {
    if services.credentialStore.hasValidatedCredentials {
      return "Validated"
    }

    if services.credentialStore.hasStoredCredentials {
      return "Needs validation"
    }

    return "Not configured"
  }

  private var healthWriteStatus: String {
    if services.healthKitService.isAuthorized {
      return "All write access allowed"
    }

    if services.healthKitService.hasAnyWritePermission {
      return "Partial write access allowed"
    }

    return "Write access incomplete"
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
