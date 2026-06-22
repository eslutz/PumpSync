import StoreKit
import SwiftUI

struct SettingsView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShowingHostedSubscriptionStore = false
  @State private var connectionAlert: ConnectionAlert?

  var body: some View {
    PumpSyncScreen(spacing: 10) {
      GlassSection("Connection") {
        connectionModeSelector

        switch services.backendConfigurationStore.mode {
        case .hosted:
          Text("Subscribe to PumpSync Hosted to securely sync pump data to Apple Health without managing your own server. Data is transmitted only during active sync operations.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

          Button {
            isShowingHostedSubscriptionStore = true
          } label: {
            GlassPrimaryLabel(
              title: "Subscribe",
              systemImage: "creditcard"
            )
          }
          .buttonStyle(GroupedRowActionButtonStyle())
          .disabled(hostedSubscriptionActionsDisabled)
          .accessibilityHint("Opens the PumpSync Hosted subscription options")

          Button {
            Task {
              await services.authService.connectHostedUsingCurrentSubscription()
              connectionAlert = restoreConnectionAlert
            }
          } label: {
            GlassPrimaryLabel(
              title: "Restore Subscription",
              systemImage: "arrow.clockwise"
            )
          }
          .buttonStyle(GroupedInlineButtonStyle())
          .disabled(hostedSubscriptionActionsDisabled)
          .accessibilityHint("Checks your current App Store subscription and reconnects hosted service access")

        case .selfHosted:
          Text("Use your own PumpSync-compatible server to sync pump data to Apple Health. You manage hosting, security, and maintenance.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

          TextField("Server URL", text: selfHostedURLBinding)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .frame(minHeight: 44)
            .accessibilityLabel("Server URL")
            .accessibilityHint("Enter the base API URL for your self-hosted PumpSync server")

          Button {
            Task {
              await services.authService.connectSelfHosted()
            }
          } label: {
            GlassPrimaryLabel(
              title: services.authService.isConnecting ? "Connecting" : "Connect",
              systemImage: "link"
            )
          }
          .buttonStyle(GroupedRowActionButtonStyle())
          .disabled(services.authService.isConnecting)
          .accessibilityHint("Connects to the self-hosted server URL")
        }

        if services.authService.isConnecting {
          HStack(spacing: 8) {
            if reduceMotion {
              Image(systemName: "hourglass")
                .accessibilityHidden(true)
            } else {
              ProgressView()
                .accessibilityHidden(true)
            }
            Text(services.authService.statusMessage)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        }
      }

      GlassSection("PumpSync") {
        NavigationLink {
          TandemCredentialForm()
        } label: {
          GlassNavigationRow("Tandem Account", subtitle: tandemAccountStatus, systemImage: "key")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("TandemAccountLink")

        GlassDivider()

        NavigationLink {
          HealthAccessView()
        } label: {
          GlassNavigationRow("Apple Health", subtitle: "Insulin and carbohydrates", systemImage: "heart")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("AppleHealthLink")

        GlassDivider()

        NavigationLink {
          InsulinConcentrationView()
        } label: {
          GlassNavigationRow(
            "Insulin Concentration",
            subtitle: services.insulinConcentrationStore.concentration.title,
            systemImage: "drop.fill"
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("InsulinConcentrationLink")

        GlassDivider()

        NavigationLink {
          DataHandlingView()
        } label: {
          GlassNavigationRow(
            "Data Handling",
            subtitle: "Privacy, retention, and Health data flow",
            systemImage: "lock.shield"
          )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DataHandlingLink")

        GlassDivider()

        NavigationLink {
          DeveloperView()
        } label: {
          GlassNavigationRow("Developer", subtitle: "Diagnostics, build, and sync details", systemImage: "hammer")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DeveloperLink")
      }
    }
    .navigationTitle("Settings")
    .sheet(isPresented: $isShowingHostedSubscriptionStore) {
      if AppLaunchEnvironment.isScreenshotMode {
        HostedSubscriptionScreenshotView()
      } else {
        HostedSubscriptionStoreView(isPresented: $isShowingHostedSubscriptionStore)
      }
    }
    .alert(item: $connectionAlert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
  }

  @ViewBuilder
  private var connectionModeSelector: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 8) {
        Text("Connection mode")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)

        ForEach(BackendAccessMode.allCases) { mode in
          let isSelected = services.backendConfigurationStore.mode == mode

          Button {
            backendModeBinding.wrappedValue = mode
          } label: {
            ConnectionModeButtonLabel(mode: mode, isSelected: isSelected)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(mode.title)
          .accessibilityValue(isSelected ? "Selected" : "Not selected")
          .accessibilityHint("Sets the connection mode to \(mode.title)")
        }
      }
      .padding(.bottom, 4)
    } else {
      Picker("Connection mode", selection: backendModeBinding) {
        ForEach(BackendAccessMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(minHeight: 44)
      .accessibilityLabel("Connection mode")
      .accessibilityValue(services.backendConfigurationStore.mode.title)
    }
  }

  private var backendModeBinding: Binding<BackendAccessMode> {
    Binding(
      get: {
        services.backendConfigurationStore.mode
      },
      set: { mode in
        services.backendConfigurationStore.mode = mode
        services.authService.clearSessionForConnectionChange()
        _ = services.backendConfigurationStore.apply(to: services.apiClient)
      }
    )
  }

  private var selfHostedURLBinding: Binding<String> {
    Binding(
      get: {
        services.backendConfigurationStore.selfHostedBaseURLString
      },
      set: { value in
        services.backendConfigurationStore.selfHostedBaseURLString = value
        if services.backendConfigurationStore.mode == .selfHosted {
          services.authService.clearSessionForConnectionChange()
          _ = services.backendConfigurationStore.apply(to: services.apiClient)
        }
      }
    )
  }

  private var restoreConnectionAlert: ConnectionAlert {
    if services.authService.isSignedIn {
      return ConnectionAlert(
        title: "Subscription Restored",
        message: "PumpSync Hosted is connected. You can now save your Tandem account."
      )
    }

    return ConnectionAlert(
      title: "Restore Failed",
      message: services.authService.connectionRequiredMessage
    )
  }

  private var hostedSubscriptionActionsDisabled: Bool {
    services.authService.isConnecting
  }

  private var tandemCredentialStatus: String {
    if services.credentialStore.hasValidatedCredentials {
      return "Validated"
    }

    if services.credentialStore.hasStoredCredentials {
      return "Needs validation"
    }

    return "Not configured"
  }

  private var tandemAccountStatus: String {
    guard let redactedUsername = services.credentialStore.redactedUsername else {
      return tandemCredentialStatus
    }

    return redactedUsername
  }

}

private struct InsulinConcentrationView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen(spacing: 16) {
      GlassSection("Current Setting") {
        Picker("Insulin Concentration", selection: insulinConcentrationBinding) {
          ForEach(InsulinConcentration.allCases) { concentration in
            Text(concentration.title).tag(concentration)
          }
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier("InsulinConcentrationPicker")
      }

      GlassSection("Details") {
        VStack(alignment: .leading, spacing: 12) {
          Text("PumpSync uses this setting only when writing insulin delivery data to Apple Health.")

          Text("Most rapid-acting insulin is U-100. Some people use more concentrated insulin, such as U-200 or U-500, where each pump-reported unit represents more insulin. Choose the concentration that matches the insulin used in your pump.")

          Text("This setting changes how PumpSync converts pump-reported insulin amounts before saving them to Apple Health. It does not change your pump data, pump account, or pump settings.")
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
      }

      GlassSection {
        Text("If you are not sure which concentration you use, leave this set to U-100 until you confirm with your insulin prescription, pump settings, or care team.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, 6)
      }
    }
    .navigationTitle("Insulin Concentration")
  }

  private var insulinConcentrationBinding: Binding<InsulinConcentration> {
    Binding(
      get: {
        services.insulinConcentrationStore.concentration
      },
      set: { concentration in
        services.insulinConcentrationStore.concentration = concentration
      }
    )
  }
}

private struct ConnectionAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

private struct ConnectionModeButtonLabel: View {
  let mode: BackendAccessMode
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        .accessibilityHidden(true)

      Text(mode.title)
        .foregroundStyle(.primary)

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
  }
}

private struct HostedSubscriptionScreenshotView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text("PumpSync Hosted")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(.primary)

        Text("Securely sync pump data to Apple Health without managing your own server.")
          .font(.title3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 16) {
        HostedSubscriptionBenefitRow(
          title: "Managed connection",
          detail: "PumpSync handles hosted service access and server maintenance.",
          systemImage: "server.rack"
        )

        HostedSubscriptionBenefitRow(
          title: "Secure Health sync",
          detail: "Data is processed only during active sync operations and is not retained on PumpSync servers.",
          systemImage: "heart.text.square"
        )

        HostedSubscriptionBenefitRow(
          title: "No server setup",
          detail: "Use the hosted service instead of deploying and maintaining your own backend.",
          systemImage: "checkmark.shield"
        )
      }

      Spacer(minLength: 24)

      Button {} label: {
        Text("Subscribe")
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
    }
    .padding(32)
    .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
    .presentationDetents([.large])
  }
}

private struct HostedSubscriptionStoreView: View {
  @Environment(AppServices.self) private var services
  @Binding var isPresented: Bool
  @State private var purchaseAlert: ConnectionAlert?

  var body: some View {
    SubscriptionStoreView(groupID: AppConstants.hostedSubscriptionGroupId) {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text("PumpSync Hosted")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)

          Text("Subscribe to securely sync pump data to Apple Health without managing your own server.")
            .font(.title3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 12) {
          HostedSubscriptionBenefitRow(
            title: "Managed connection",
            detail: "PumpSync handles hosted service access and server maintenance.",
            systemImage: "server.rack"
          )

          HostedSubscriptionBenefitRow(
            title: "Secure Health sync",
            detail: "Sync through PumpSync's hosted service. Data is processed only during active sync operations and is not retained on PumpSync servers.",
            systemImage: "heart.text.square"
          )

          HostedSubscriptionBenefitRow(
            title: "No server setup",
            detail: "Use the hosted service instead of deploying and maintaining your own backend.",
            systemImage: "checkmark.shield"
          )
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.top, 24)
    }
    .subscriptionStoreButtonLabel(.action)
    .onInAppPurchaseCompletion { _, result in
      await handlePurchaseCompletion(result)
    }
    .alert(item: $purchaseAlert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
    }
  }

  private func handlePurchaseCompletion(_ result: Result<Product.PurchaseResult, Error>) async {
    switch result {
    case .success(.success(let verificationResult)):
      do {
        let transaction = try verified(verificationResult)
        await services.authService.activateHostedSubscription(signedTransactionInfo: verificationResult.jwsRepresentation)
        await transaction.finish()
        if services.authService.isSignedIn {
          isPresented = false
        } else {
          purchaseAlert = ConnectionAlert(
            title: "Subscription Verification Failed",
            message: services.authService.connectionRequiredMessage
          )
        }
      } catch {
        services.authService.recordHostedSubscriptionPurchaseFailed(error)
        purchaseAlert = ConnectionAlert(
          title: "Subscription Verification Failed",
          message: services.authService.connectionRequiredMessage
        )
      }
    case .success(.userCancelled):
      services.authService.recordHostedSubscriptionPurchaseCancelled()
    case .success(.pending):
      services.authService.recordHostedSubscriptionPurchasePending()
      purchaseAlert = ConnectionAlert(
        title: "Subscription Pending",
        message: services.authService.statusMessage
      )
    case .failure(let error):
      services.authService.recordHostedSubscriptionPurchaseFailed(error)
      purchaseAlert = ConnectionAlert(
        title: "Subscription Failed",
        message: services.authService.connectionRequiredMessage
      )
    @unknown default:
      services.authService.recordHostedSubscriptionPurchaseFailed(StoreKitSubscriptionError.unverifiedTransaction)
      purchaseAlert = ConnectionAlert(
        title: "Subscription Failed",
        message: services.authService.connectionRequiredMessage
      )
    }
  }

  private func verified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let value):
      return value
    case .unverified:
      throw StoreKitSubscriptionError.unverifiedTransaction
    }
  }
}

private struct HostedSubscriptionBenefitRow: View {
  let title: String
  let detail: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.blue)
        .frame(width: 28)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(detail)
  }
}
