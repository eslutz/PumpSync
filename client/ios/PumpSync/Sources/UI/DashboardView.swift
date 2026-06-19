import SwiftUI

struct DashboardView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      GlassSection {
        GlassStatusRow(
          title: "Connection",
          value: services.authService.isSignedIn ? services.authService.statusMessage : "Not connected",
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "network.badge.shield.half.filled"
        )

        GlassDivider()

        GlassStatusRow(
          title: "Tandem",
          value: tandemStatus,
          systemImage: services.credentialStore.hasValidatedCredentials ? "key.fill" : "key.slash"
        )

        GlassDivider()

        GlassStatusRow(
          title: "Last sync",
          value: formattedDate(services.syncMetadataStore.metadata.lastSuccessfulSyncAt),
          systemImage: "clock.arrow.circlepath"
        )
      }

      Button {
        Task {
          if canSync {
            await services.syncCoordinator.sync(reason: .manual)
          }
        }
      } label: {
        GlassPrimaryLabel(title: services.syncCoordinator.isSyncing ? "Syncing" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canSync)

      ForEach(
        Self.dashboardMessages(
          isBackendConnected: services.authService.isSignedIn,
          hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
          hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission
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
      if canSync {
        await services.syncCoordinator.sync(reason: .manual)
      }
    }
  }

  private var canSync: Bool {
    services.authService.isSignedIn
      && services.credentialStore.hasValidatedCredentials
      && services.healthKitService.hasAnyWritePermission
      && !services.syncCoordinator.isSyncing
  }

  private var tandemStatus: String {
    if services.credentialStore.hasValidatedCredentials {
      return "Validated"
    }

    if services.credentialStore.hasStoredCredentials {
      return "Needs validation"
    }

    return "Not configured"
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  static func dashboardMessages(
    isBackendConnected: Bool,
    hasValidatedCredentials: Bool,
    hasAnyHealthWritePermission: Bool
  ) -> [String] {
    if !isBackendConnected {
      return []
    }

    if !hasValidatedCredentials {
      return ["Validate Tandem credentials in Settings before syncing."]
    }

    if !hasAnyHealthWritePermission {
      return ["Enable at least one Apple Health write permission before syncing."]
    }

    return []
  }
}
