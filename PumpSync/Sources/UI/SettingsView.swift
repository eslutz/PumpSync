import SwiftUI

private enum SettingsDestination: Hashable {
  case subscription
}

struct SettingsView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.editingScreenDepartureID) private var editingScreenDepartureID
  @State private var connectionTask: Task<Void, Never>?

  private var connectionFeedback: String {
    let connection = services.connectionSettings
    return connection.isConnecting || connection.feedback != nil
      ? connection.connectionDescription : ""
  }

  var body: some View {
    Form {
      ConnectionConfigurationSection(
        mode: Binding(get: { services.connectionSettings.mode }, set: { services.connectionSettings.mode = $0 }),
        serverURL: Binding(get: { services.connectionSettings.serverURL }, set: { services.connectionSettings.serverURL = $0 }),
        subscriptionStatus: services.authService.subscriptionAccessStatus,
        isConnecting: services.connectionSettings.isConnecting,
        canConnect: services.connectionSettings.canConnect,
        feedback: connectionFeedback,
        connect: { connectionTask = Task { await services.connectionSettings.connect() } }
      )

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
        Text("App").foregroundStyle(Color.primary)
      }
      .headerProminence(.increased)
    }
    .font(.body)
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Settings")
    .navigationDestination(for: SettingsDestination.self) { destination in
      switch destination {
      case .subscription: SubscriptionSettingsView()
      }
    }
    .onAppear(perform: discardDraft)
    .onDisappear(perform: discardDraft)
    .onChange(of: editingScreenDepartureID) { _, _ in discardDraft() }
    .task {
      if !AppLaunchEnvironment.isScreenshotMode {
        await services.authService.refreshSubscriptionStatus()
      }
    }
  }

  private func discardDraft() {
    connectionTask?.cancel()
    connectionTask = nil
    services.connectionSettings.cancel()
  }
}

/// This feature section composes platform controls; the Form owns all row styling.
private struct ConnectionConfigurationSection: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var mode: BackendAccessMode
  @Binding var serverURL: String
  let subscriptionStatus: SubscriptionAccessStatus
  let isConnecting: Bool
  let canConnect: Bool
  let feedback: String
  let connect: () -> Void
  @FocusState private var isServerURLFocused: Bool

  var body: some View {
    Section {
      if dynamicTypeSize.isAccessibilitySize {
        modePicker.pickerStyle(.menu)
      } else {
        modePicker.pickerStyle(.segmented)
      }

      if mode == .selfHosted {
        TextField("Server URL", text: $serverURL, prompt: Text("https://your-server.example/api"))
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
          .autocorrectionDisabled()
          .accessibilityLabel("Server URL")
          .accessibilityIdentifier("ServerURLField")
          .disabled(isConnecting)
          .focused($isServerURLFocused)
          .submitLabel(.done)
          .onSubmit { isServerURLFocused = false }
        Button {
          isServerURLFocused = false
          connect()
        } label: {
          Label {
            Text("Connect")
          } icon: {
            Image(systemName: "link")
              .opacity(isConnecting ? 0 : 1)
              .overlay {
                if isConnecting { ProgressView().controlSize(.small) }
              }
              .accessibilityHidden(true)
          }
        }
        .accessibilityValue(isConnecting ? Text("Connecting") : Text(""))
        .disabled(!canConnect || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      if mode == .hosted {
        NavigationLink(value: SettingsDestination.subscription) {
          LabeledContent("Subscription") {
            Text(subscriptionStatus.title).foregroundStyle(Color.primary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityIdentifier("SubscriptionSettingsLink")
      }

      if !isConnecting && !feedback.isEmpty {
        Text(feedback)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("SelfHostedConnectionFeedback")
      }

      if mode == .hosted {
        Text("Your subscription configures the PumpSync service. Changing connection mode does not cancel your subscription.")
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } header: {
      Text("Connection Configuration").foregroundStyle(Color.primary)
    }
    .headerProminence(.increased)
    .font(.body)
  }

  private var modePicker: some View {
    Picker("Connection mode", selection: $mode) {
      ForEach(BackendAccessMode.allCases) { mode in Text(mode.title).tag(mode) }
    }
    .accessibilityIdentifier("ConnectionModePicker")
    .disabled(isConnecting)
    .onChange(of: mode) { _, _ in isServerURLFocused = false }
  }
}

#if DEBUG
#Preview("Hosted subscription") {
  NavigationStack {
    Form {
      ConnectionConfigurationSection(mode: .constant(.hosted), serverURL: .constant(""),
        subscriptionStatus: .active,
        isConnecting: false, canConnect: true, feedback: "", connect: {})
    }
    .navigationTitle("Settings")
  }
}

#Preview("Self-hosted draft at large text") {
  NavigationStack {
    Form {
      ConnectionConfigurationSection(mode: .constant(.selfHosted), serverURL: .constant("https://example.com/api"),
        subscriptionStatus: .active,
        isConnecting: false, canConnect: true, feedback: "", connect: {})
    }
    .navigationTitle("Settings")
    .dynamicTypeSize(.accessibility3)
  }
}
#endif
