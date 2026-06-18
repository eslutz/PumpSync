import SwiftUI

struct SyncView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen {
      if services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil {
        GlassSection("Initial Import") {
          Picker("History", selection: initialImportRangeBinding) {
            ForEach(InitialImportRange.allCases) { range in
              Text(range.title).tag(range)
            }
          }
          .pickerStyle(.menu)

          GlassDivider()

          Text("PumpSync will import Tandem insulin and carbohydrate history for this range, if available. Then future syncs will only import new data.")
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
        }
      }

      GlassEffectContainer(spacing: 16) {
        Button {
          Task {
            await services.syncCoordinator.sync(reason: .manual)
          }
        } label: {
          GlassPrimaryLabel(title: syncButtonTitle, systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!services.authService.isSignedIn || !services.credentialStore.hasStoredCredentials || services.syncCoordinator.isSyncing)
      }

      if let message = Self.readinessMessage(
        isSignedIn: services.authService.isSignedIn,
        hasStoredCredentials: services.credentialStore.hasStoredCredentials
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

  private var initialImportRangeBinding: Binding<InitialImportRange> {
    Binding(
      get: {
        services.syncMetadataStore.metadata.initialImportRange
      },
      set: { range in
        services.syncMetadataStore.setInitialImportRange(range)
      }
    )
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

  static func readinessMessage(isSignedIn: Bool, hasStoredCredentials: Bool) -> String? {
    if !isSignedIn {
      return "Sign in from Settings before syncing."
    }

    if !hasStoredCredentials {
      return "Add Tandem credentials in Settings before syncing."
    }

    return nil
  }
}
