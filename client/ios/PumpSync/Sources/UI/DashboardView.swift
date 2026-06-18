import SwiftUI

struct DashboardView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    List {
      Section {
        statusRow(
          title: "Apple account",
          value: services.authService.statusMessage,
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark"
        )

        statusRow(
          title: "Tandem",
          value: services.credentialStore.hasStoredCredentials ? "Saved on this device" : "Not configured",
          systemImage: services.credentialStore.hasStoredCredentials ? "key.fill" : "key.slash"
        )

        statusRow(
          title: "Last sync",
          value: formattedDate(services.syncMetadataStore.metadata.lastSuccessfulSyncAt),
          systemImage: "clock.arrow.circlepath"
        )
      }

      Section {
        Button {
          Task {
            await services.syncCoordinator.sync(reason: .manual)
          }
        } label: {
          Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!services.authService.isSignedIn || services.syncCoordinator.isSyncing)
      }

      ForEach(
        Self.dashboardMessages(
          isSignedIn: services.authService.isSignedIn,
          syncMessage: services.syncCoordinator.lastMessage,
          authErrorMessage: services.authService.errorMessage,
          lastSyncErrorMessage: services.syncMetadataStore.metadata.lastErrorMessage
        ),
        id: \.self
      ) { message in
        Section {
          Text(message)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("PumpSync")
    .refreshable {
      await services.syncCoordinator.sync(reason: .manual)
    }
  }

  private func statusRow(title: String, value: String, systemImage: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .frame(width: 24)
        .foregroundStyle(.tint)

      VStack(alignment: .leading) {
        Text(title)
        Text(value)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private func formattedDate(_ date: Date?) -> String {
    guard let date else {
      return "Never"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
  }

  static func dashboardMessages(
    isSignedIn: Bool,
    syncMessage: String?,
    authErrorMessage: String?,
    lastSyncErrorMessage: String?
  ) -> [String] {
    if let syncMessage {
      return [syncMessage]
    }

    if let authErrorMessage {
      return [authErrorMessage]
    }

    if isSignedIn {
      return lastSyncErrorMessage.map { [$0] } ?? []
    }

    return ["Sign in from Settings before syncing."]
  }
}
