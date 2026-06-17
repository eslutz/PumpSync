import AuthenticationServices
import SwiftUI

struct DashboardView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    List {
      Section {
        statusRow(
          title: "Apple account",
          value: services.authService.isSignedIn ? "Signed in" : "Not signed in",
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
            await services.authService.signIn()
          }
        } label: {
          Label(services.authService.isSignedIn ? "Refresh Apple Session" : "Sign in with Apple", systemImage: "apple.logo")
        }
        .disabled(services.authService.isSigningIn)

        Button {
          Task {
            await services.syncCoordinator.sync(reason: .manual)
          }
        } label: {
          Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(services.syncCoordinator.isSyncing)
      }

      if let message = services.syncCoordinator.lastMessage ?? services.authService.errorMessage ?? services.syncMetadataStore.metadata.lastErrorMessage {
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
}
