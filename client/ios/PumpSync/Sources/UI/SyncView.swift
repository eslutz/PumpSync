import SwiftUI

struct SyncView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    List {
      Section("Manual Sync") {
        Button {
          Task {
            await services.syncCoordinator.sync(reason: .manual)
          }
        } label: {
          Label(services.syncCoordinator.isSyncing ? "Syncing" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
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

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }
}
