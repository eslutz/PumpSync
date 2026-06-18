import SwiftUI

struct SyncView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    List {
      if services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil {
        Section("Initial Import") {
          Picker("History", selection: initialImportRangeBinding) {
            ForEach(InitialImportRange.allCases) { range in
              Text(range.title).tag(range)
            }
          }

          Text("PumpSync will import Tandem insulin and carbohydrate history for this range, if available. Then future syncs will only import new data.")
            .foregroundStyle(.secondary)
        }
      }

      Section(services.syncMetadataStore.metadata.lastSuccessfulSyncAt == nil ? "Initial Sync" : "Manual Sync") {
        Button {
          Task {
            await services.syncCoordinator.sync(reason: .manual)
          }
        } label: {
          Label(syncButtonTitle, systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(services.syncCoordinator.isSyncing)
      }

      Section("Latest Result") {
        LabeledContent("Attempt", value: formattedDate(services.syncMetadataStore.metadata.lastAttemptAt))
        LabeledContent("Success", value: formattedDate(services.syncMetadataStore.metadata.lastSuccessfulSyncAt))
        LabeledContent("Returned", value: "\(services.syncMetadataStore.metadata.lastSampleCount)")
        LabeledContent("Imported", value: "\(services.syncMetadataStore.metadata.lastImportedCount)")
      }

      Section("Daily Background Sync") {
        Text("iOS grants background processing opportunistically. PumpSync schedules a daily network task and also refreshes stale data when the app opens.")
          .foregroundStyle(.secondary)

        Button {
          services.backgroundSyncScheduler.scheduleDailySync()
          services.syncCoordinator.recordDailySyncRequested()
        } label: {
          Label("Request Daily Sync", systemImage: "calendar.badge.clock")
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
}
