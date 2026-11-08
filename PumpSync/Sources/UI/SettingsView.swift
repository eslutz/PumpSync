import SwiftUI

struct SettingsView: View {
  @Environment(AppServices.self) private var services
  @State private var connectionTask: Task<Void, Never>?

  private var connectionFeedback: String {
    let connection = services.connectionSettings
    return connection.hasChanges || connection.isConnecting || !services.authService.isSignedIn || connection.feedback != nil
      ? connection.connectionDescription : ""
  }

  var body: some View {
    Form {
      ConnectionConfigurationSection(
        mode: Binding(get: { services.connectionSettings.mode }, set: { services.connectionSettings.mode = $0 }),
        serverURL: Binding(get: { services.connectionSettings.serverURL }, set: { services.connectionSettings.serverURL = $0 }),
        subscriptionStatus: services.authService.subscriptionAccessStatus,
        activeService: services.authService.isSignedIn ? services.backendConfigurationStore.mode.title : nil,
        hasChanges: services.connectionSettings.hasChanges,
        isConnecting: services.connectionSettings.isConnecting,
        canConnect: services.connectionSettings.canConnect,
        feedback: connectionFeedback,
        connect: { connectionTask = Task { await services.connectionSettings.connect() } },
        cancel: {
          connectionTask?.cancel()
          services.connectionSettings.cancel()
        }
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
    .task {
      if !AppLaunchEnvironment.isScreenshotMode {
        await services.authService.refreshSubscriptionStatus()
      }
    }
  }
}

/// This feature section composes platform controls; the Form owns all row styling.
private struct ConnectionConfigurationSection: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Binding var mode: BackendAccessMode
  @Binding var serverURL: String
  let subscriptionStatus: SubscriptionAccessStatus
  let activeService: String?
  let hasChanges: Bool
  let isConnecting: Bool
  let canConnect: Bool
  let feedback: String
  let connect: () -> Void
  let cancel: () -> Void
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
        Text("Use an HTTPS base API URL ending in /api. You manage hosting, security, and maintenance.")
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
        Button(isConnecting ? "Connecting" : "Connect", systemImage: "link") {
          isServerURLFocused = false
          connect()
        }
        .buttonStyle(.glassProminent)
        .tint(Color("ProminentActionColor"))
        .controlSize(.large)
        .disabled(!canConnect || BackendConfigurationStore.validatedSelfHostedURL(from: serverURL) == nil)
      }

      NavigationLink {
        SubscriptionSettingsView()
      } label: {
        LabeledContent("Subscription") {
          Text(subscriptionStatus.title).foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .accessibilityIdentifier("SubscriptionSettingsLink")

      if isConnecting {
        HStack {
          ProgressView()
          Text(feedback)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
      } else if hasChanges || !feedback.isEmpty {
        Text(feedback)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("SelfHostedConnectionFeedback")
      }

      if hasChanges || isConnecting {
        if let activeService {
          Text("Currently connected to \(activeService)")
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button("Cancel Changes", role: .cancel) {
          isServerURLFocused = false
          cancel()
        }
      }
      Text(mode == .hosted
        ? "Your subscription configures the PumpSync service. Manage or restore it from Subscription. Changing connection mode does not cancel your subscription."
        : "Connect validates the new service using your pump account. Sync and source inspection continue using the current service until the new connection succeeds.")
        .foregroundStyle(Color.primary)
        .fixedSize(horizontal: false, vertical: true)
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
        subscriptionStatus: .active, activeService: "PumpSync", hasChanges: false,
        isConnecting: false, canConnect: true, feedback: "", connect: {}, cancel: {})
    }
    .navigationTitle("Settings")
  }
}

#Preview("Self-hosted draft at large text") {
  NavigationStack {
    Form {
      ConnectionConfigurationSection(mode: .constant(.selfHosted), serverURL: .constant("https://example.com/api"),
        subscriptionStatus: .active, activeService: "PumpSync", hasChanges: true,
        isConnecting: false, canConnect: true, feedback: "Changes take effect only after connection succeeds. Your current setup remains active.", connect: {}, cancel: {})
    }
    .navigationTitle("Settings")
    .dynamicTypeSize(.accessibility3)
  }
}
#endif
