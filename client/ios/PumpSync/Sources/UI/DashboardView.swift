import SwiftUI

struct DashboardView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      GlassSection {
        GlassStatusRow(
          title: "Apple account",
          value: services.authService.isSignedIn ? services.authService.statusMessage : "Not signed in.",
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark"
        )

        GlassDivider()

        GlassStatusRow(
          title: "Tandem",
          value: services.credentialStore.hasStoredCredentials ? "Saved on this device" : "Not configured",
          systemImage: services.credentialStore.hasStoredCredentials ? "key.fill" : "key.slash"
        )

        GlassDivider()

        GlassStatusRow(
          title: "Last sync",
          value: formattedDate(services.syncMetadataStore.metadata.lastSuccessfulSyncAt),
          systemImage: "clock.arrow.circlepath"
        )
      }

      GlassEffectContainer(spacing: 16) {
        Button {
          Task {
            await services.syncCoordinator.sync(reason: .manual)
          }
        } label: {
          GlassPrimaryLabel(title: services.syncCoordinator.isSyncing ? "Syncing" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!services.authService.isSignedIn || services.syncCoordinator.isSyncing)
      }

      ForEach(
        Self.dashboardMessages(
          isSignedIn: services.authService.isSignedIn,
          hasStoredCredentials: services.credentialStore.hasStoredCredentials,
          isHealthAuthorized: services.healthKitService.isAuthorized
        ),
        id: \.self
      ) { message in
        GlassSection {
          Text(message)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .navigationTitle("PumpSync")
    .refreshable {
      await services.syncCoordinator.sync(reason: .manual)
    }
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  static func dashboardMessages(
    isSignedIn: Bool,
    hasStoredCredentials: Bool,
    isHealthAuthorized: Bool
  ) -> [String] {
    if !isSignedIn {
      return ["Sign in from Settings before syncing."]
    }

    if !hasStoredCredentials {
      return ["Add Tandem credentials in Settings before syncing."]
    }

    if !isHealthAuthorized {
      return ["Manage Apple Health access in Settings before syncing."]
    }

    return []
  }
}
