import SwiftUI

struct SettingsView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    Form {
      Section {
        NavigationLink {
          TandemCredentialForm()
        } label: {
          LabeledContent {
            Text(services.credentialStore.redactedUsername ?? "Not configured")
              .foregroundStyle(Color.primary)
              .fixedSize(horizontal: false, vertical: true)
          } label: {
            Label("Tandem Account", systemImage: "key")
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityIdentifier("TandemAccountLink")

        NavigationLink { HealthAccessView() } label: {
          Label("Apple Health", systemImage: "heart").fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("AppleHealthLink")

        NavigationLink {
          InsulinConcentrationView()
        } label: {
          LabeledContent {
            Text(services.insulinConcentrationStore.concentration.title)
              .foregroundStyle(Color.primary)
              .fixedSize(horizontal: false, vertical: true)
          } label: {
            Label("Insulin Concentration", systemImage: "drop.fill")
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityIdentifier("InsulinConcentrationLink")

        NavigationLink { DataHandlingView() } label: {
          Label("Data Handling", systemImage: "lock.shield").fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("DataHandlingLink")
        NavigationLink { AboutPumpSyncView() } label: {
          Label("About PumpSync", systemImage: "info.circle").fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("AboutPumpSyncLink")
        NavigationLink { DeveloperView() } label: {
          Label("Developer", systemImage: "hammer").fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("DeveloperLink")
      } header: {
        Text("PumpSync").foregroundStyle(Color.primary)
      }
      .headerProminence(.increased)
    }
    .font(.body)
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Settings")
  }
}
