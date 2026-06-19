import SwiftUI

struct SyncView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      if services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil {
        GlassSection("Initial Import") {
          initialImportMenu

          GlassDivider()

          Text("PumpSync will import Tandem insulin and carbohydrate history for this range, if available. Then future syncs will only import new data.")
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
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
          Text("After the first sync, PumpSync refreshes stale data when the app opens and schedules daily background updates when iOS grants time.")
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
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 2) {
          Text("History")
            .foregroundStyle(.primary)

          Text(services.syncMetadataStore.metadata.initialImportRange.title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)

        Image(systemName: "chevron.up.chevron.down")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.tertiary)
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
      return "Validate Tandem credentials in Settings before syncing."
    }

    if !hasAnyHealthWritePermission {
      return "Enable at least one Apple Health write permission before syncing."
    }

    return nil
  }
}
