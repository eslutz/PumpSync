import SwiftUI

struct SyncView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      GlassSection {
        GlassStatusRow(
          title: "Connection",
          value: connectionStatus,
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "network.badge.shield.half.filled"
        )

        GlassDivider()

        GlassStatusRow(
          title: "Pump data",
          value: tandemStatus,
          systemImage: services.credentialStore.hasValidatedCredentials ? "key.fill" : "key.slash"
        )
      }

      if services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil {
        GlassSection("Initial Import") {
          initialImportMenu

          GlassDivider(leadingPadding: 0)

          VStack(alignment: .leading, spacing: 10) {
            Text("Choose how much pump history to import the first time. Future syncs import new data only.")

            Text("After the first sync, PumpSync checks for new pump data when the app opens and during daily background updates when iOS grants time.")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
        }
      }

      Button {
        Task {
          if canSync {
            await services.syncCoordinator.sync(reason: .manual)
          }
        }
      } label: {
        GlassPrimaryLabel(title: syncButtonTitle, systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canSync)

      if let message = Self.readinessMessage(
        isBackendConnected: services.authService.isSignedIn,
        hasValidatedCredentials: services.credentialStore.hasValidatedCredentials,
        hasAnyHealthWritePermission: services.healthKitService.hasAnyWritePermission
      ) {
        GlassSection {
          Text(message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.secondary)
        }
      }

      if let lastSuccessfulSyncAt = services.syncMetadataStore.metadata.lastSuccessfulSyncAt {
        GlassSection("Last Sync") {
          GlassStatusRow(
            title: "Completed",
            value: formattedDate(lastSuccessfulSyncAt),
            systemImage: "checkmark.circle.fill",
            tint: .green
          )
        }
      }
    }
    .navigationTitle("Sync")
    .onAppear {
      services.healthKitService.refreshAuthorizationStatus()
    }
  }

  private var initialImportMenu: some View {
    Menu {
      ForEach(InitialImportRange.allCases) { range in
        Button {
          services.syncMetadataStore.setInitialImportRange(range)
        } label: {
          if range == services.syncMetadataStore.metadata.initialImportRange {
            Label(range.title, systemImage: "checkmark")
          } else {
            Text(range.title)
          }
        }
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "calendar.badge.clock")
          .font(.title3)
          .frame(width: 28)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 3) {
          Text("History range")
            .foregroundStyle(.primary)

          Text(services.syncMetadataStore.metadata.initialImportRange.title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)

        Text("Change")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.tint)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("History range")
    .accessibilityValue(services.syncMetadataStore.metadata.initialImportRange.title)
    .accessibilityHint("Changes how much pump history to import during the first sync")
  }

  private var canSync: Bool {
    services.authService.isSignedIn
      && services.credentialStore.hasValidatedCredentials
      && services.healthKitService.hasAnyWritePermission
      && !services.syncCoordinator.isSyncing
  }

  private var connectionStatus: String {
    services.authService.isSignedIn ? "Connected" : "Not connected"
  }

  private var tandemStatus: String {
    if services.credentialStore.hasValidatedCredentials {
      return "Ready"
    }

    if services.credentialStore.hasStoredCredentials {
      return "Needs validation"
    }

    return "Not configured"
  }

  private var syncButtonTitle: String {
    if services.syncCoordinator.isSyncing {
      return "Syncing"
    }

    return services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil ? "Start Initial Sync" : "Sync Now"
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  static func readinessMessage(
    isBackendConnected: Bool,
    hasValidatedCredentials: Bool,
    hasAnyHealthWritePermission: Bool
  ) -> String? {
    if !isBackendConnected {
      return nil
    }

    if !hasValidatedCredentials {
      return "Save your pump account credentials in Settings before syncing."
    }

    if !hasAnyHealthWritePermission {
      return "Enable at least one Apple Health write permission before syncing."
    }

    return nil
  }
}
