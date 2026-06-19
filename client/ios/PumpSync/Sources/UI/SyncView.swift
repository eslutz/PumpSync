import SwiftUI

struct SyncView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      if services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil {
        GlassSection("Initial Import") {
          initialImportMenu

          GlassDivider(leadingPadding: 0)

          Text("Choose how much pump history to import the first time. Future syncs import new data only.")
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
      } else {
        GlassSection("Automatic Sync") {
          Text("After the first sync, PumpSync checks for new pump data when the app opens and during daily background updates when iOS grants time.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .navigationTitle("Sync")
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
  }

  private var canSync: Bool {
    services.authService.isSignedIn
      && services.credentialStore.hasValidatedCredentials
      && services.healthKitService.hasAnyWritePermission
      && !services.syncCoordinator.isSyncing
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
      return "Validate your pump account in Settings before syncing."
    }

    if !hasAnyHealthWritePermission {
      return "Enable at least one Apple Health write permission before syncing."
    }

    return nil
  }
}
