import StoreKit
import SwiftUI
import UIKit

struct SettingsView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var connectionAlert: ConnectionAlert?
  @State private var purchaseRequest: SubscriptionConnectionRequest?
  @State private var connectionTask: Task<Void, Never>?
  @FocusState private var isServerURLFocused: Bool

  var body: some View {
    PumpSyncScreen(spacing: 10) {
      GlassSection("Connection") {
        connectionModeSelector.disabled(services.connectionSettings.isConnecting)
        if services.authService.isSignedIn {
          GlassStatusRow(title: "Active service", value: services.backendConfigurationStore.mode.title, systemImage: "checkmark.circle")
        }
        switch services.connectionSettings.mode {
        case .hosted:
          if !hasActiveHostedConnection {
            Text("Connect through PumpSync without managing a server.")
              .foregroundStyle(Color.pumpSyncSecondaryText).padding(.vertical, 8)
          }
          subscriptionAction
          Button("Restore Subscription", systemImage: "arrow.clockwise") { connectDraft() }
            .buttonStyle(.bordered).tint(.primary).controlSize(.large).disabled(subscriptionActionsDisabled)
        case .selfHosted:
          Text("You manage hosting, security, and maintenance.").foregroundStyle(Color.pumpSyncSecondaryText).padding(.vertical, 8)
          Text("Server URL").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
          TextField("https://your-server.example/api", text: Binding(
            get: { services.connectionSettings.serverURL }, set: { services.connectionSettings.serverURL = $0 }))
            .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
            .frame(minHeight: 44).accessibilityLabel("Server URL").accessibilityIdentifier("ServerURLField")
            .disabled(services.connectionSettings.isConnecting)
            .focused($isServerURLFocused)
            .submitLabel(.done)
            .onSubmit { isServerURLFocused = false }
          Text("Use the base API URL ending in /api.").font(.subheadline).foregroundStyle(.primary)
          Button { connectDraft() } label: {
            Label(services.connectionSettings.isConnecting ? "Connecting" : "Connect", systemImage: "link")
              .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
          }
          .buttonStyle(.borderedProminent).controlSize(.large).font(.title3.weight(.semibold)).disabled(!services.connectionSettings.canConnect)
        }
        Text("Pump account details are sent to the selected service when validating, syncing, or inspecting source data.")
          .font(.subheadline).foregroundStyle(.primary).padding(.vertical, 8)
        if services.connectionSettings.isConnecting {
          HStack {
            if reduceMotion { Image(systemName: "hourglass").accessibilityHidden(true) }
            else { ProgressView().accessibilityHidden(true) }
            Text(services.connectionSettings.connectionDescription).fixedSize(horizontal: false, vertical: true)
          }.accessibilityElement(children: .combine)
        } else {
          Text(services.connectionSettings.connectionDescription)
            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("SelfHostedConnectionFeedback")
        }
        if services.connectionSettings.hasChanges || services.connectionSettings.isConnecting {
          Button("Cancel Changes", role: .cancel) {
            isServerURLFocused = false
            connectionTask?.cancel()
            services.connectionSettings.cancel()
          }.tint(.primary).frame(minHeight: 44)
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
          AboutPumpSyncView()
        } label: {
          GlassNavigationRow("About PumpSync", subtitle: "How syncing works", systemImage: "info.circle")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("AboutPumpSyncLink")

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
    .sheet(item: $purchaseRequest) { request in
      Group {
#if DEBUG
        if AppLaunchEnvironment.isScreenshotMode { SubscriptionScreenshotView() }
        else { subscriptionStore(request) }
#else
        subscriptionStore(request)
#endif
      }
      .onDisappear { services.connectionSettings.finishSubscription(request, verified: false) }
    }
    .alert(
      connectionAlert?.title ?? "",
      isPresented: Binding(
        get: { connectionAlert != nil },
        set: { isPresented in
          if !isPresented {
            connectionAlert = nil
          }
        }
      ),
      presenting: connectionAlert
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { alert in
      Text(alert.message)
    }
  }

  private var hasActiveHostedConnection: Bool {
    services.authService.isSignedIn && services.backendConfigurationStore.mode == .hosted
  }

  @ViewBuilder private var subscriptionAction: some View {
    let action = Button {
      purchaseRequest = services.connectionSettings.prepareSubscription()
    } label: {
      Label(hasActiveHostedConnection ? "Subscription Options" : "Subscribe", systemImage: "creditcard")
        .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
    }
    .controlSize(.large).font(.title3.weight(.semibold))
    .disabled(subscriptionActionsDisabled)
    if hasActiveHostedConnection { action.buttonStyle(.bordered).tint(.primary) }
    else { action.buttonStyle(.borderedProminent) }
  }

  private func subscriptionStore(_ request: SubscriptionConnectionRequest) -> some View {
    PumpSyncSubscriptionStoreView(isPresented: Binding(get: { purchaseRequest?.id == request.id }, set: { if !$0 && purchaseRequest?.id == request.id { purchaseRequest = nil } }),
      authServiceOverride: request.auth,
      onConnectionVerified: { services.connectionSettings.finishSubscription(request, verified: true) },
      onConnectionAttemptFinished: { services.connectionSettings.subscriptionAttemptFinished(request) })
  }

  @ViewBuilder
  private var connectionModeSelector: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 8) {
        Text("Connection mode")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.pumpSyncSecondaryText)

        ForEach(BackendAccessMode.allCases) { mode in
          let isSelected = services.connectionSettings.mode == mode

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
      .accessibilityValue(services.connectionSettings.mode.title)
    }
  }

  private var backendModeBinding: Binding<BackendAccessMode> {
    Binding(get: { services.connectionSettings.mode }, set: {
      isServerURLFocused = false
      services.connectionSettings.mode = $0
    })
  }

  private func connectDraft() {
    guard services.connectionSettings.canConnect else { return }
    connectionTask = Task { await services.connectionSettings.connect() }
  }

  private var restoreConnectionAlert: ConnectionAlert {
    if services.authService.isSignedIn {
      return ConnectionAlert(
        title: "Subscription Restored",
        message: "PumpSync Subscription is connected. You can now save your Tandem account."
      )
    }

    return ConnectionAlert(
      title: "Restore Failed",
      message: services.authService.connectionRequiredMessage
    )
  }

  private var subscriptionActionsDisabled: Bool {
    !services.connectionSettings.canConnect
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen(spacing: 16) {
      GlassSection("Current Setting") {
        concentrationMenu
      }

      Text("Applies to the next sync. A running sync keeps its starting setting. Changes the insulin amounts saved to Apple Health; it does not change pump settings or previously imported records.")
        .fixedSize(horizontal: false, vertical: true)
      Label("Confirm the setting against your insulin prescription, pump configuration, or care team before changing it.", systemImage: "exclamationmark.triangle")
        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
      NavigationLink {
        PumpSyncScreen {
      GlassSection("Details") {
        InsulinConcentrationDetailRow(
          title: "Match your insulin",
          detail: "Most rapid-acting insulin is U-100. Some people use more concentrated insulin, such as U-200 or U-500, where each pump-reported unit represents more insulin.",
          systemImage: "drop"
        )

        GlassDivider()

        InsulinConcentrationDetailRow(
          title: "Conversion only",
          detail: "This changes how PumpSync converts pump-reported insulin amounts before saving them to Apple Health. It does not change your pump data, pump account, or pump settings.",
          systemImage: "arrow.triangle.2.circlepath"
        )

        GlassDivider()

        InsulinConcentrationDetailRow(
          title: "Apple Health only",
          detail: "Changes apply to the next sync. A sync already running keeps its starting setting. Previously imported Apple Health data is not changed.",
          systemImage: "heart"
        )

        GlassDivider()

        InsulinConcentrationDetailRow(
          title: "Not sure?",
          detail: "Leave this set to U-100 until you confirm with your insulin prescription, pump settings, or care team.",
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange
        )
      }
        }.navigationTitle("Insulin Conversion").navigationBarTitleDisplayMode(.inline)
      } label: {
        GlassNavigationRow("How Insulin Conversion Works", systemImage: "info.circle")
      }
      .buttonStyle(.plain)
      .frame(minHeight: 44)

    }
    .navigationTitle("Insulin Concentration")
  }

  private var concentrationMenu: some View {
    LabeledMenuPickerRow(title: "Insulin Concentration", systemImage: "drop.fill") {
        NativeMenuPicker("Insulin Concentration", selection: Binding(
          get: { services.insulinConcentrationStore.concentration },
          set: { services.insulinConcentrationStore.concentration = $0 }
        )) {
          ForEach(InsulinConcentration.allCases) { concentration in
            Text(concentration.title).tag(concentration)
          }
        }
        .accessibilityIdentifier("InsulinConcentrationPicker")
    }
  }

}

private struct InsulinConcentrationDetailRow: View {
  let title: String
  let detail: String
  let systemImage: String
  var tint: Color = .accentColor

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: systemImage)
        .rowIconColumn()
        .foregroundStyle(tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .foregroundStyle(.primary)

        Text(detail)
          .font(.subheadline)
          .foregroundStyle(Color.pumpSyncSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .layoutPriority(1)

      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(detail)
  }
}

private struct ConnectionAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
  var action: ConnectionAlertAction?
}

private enum ConnectionAlertAction {
  case manageSubscription
}

enum SubscriptionPresentation {
  static func shouldDismissAfterManageSubscriptions(isSignedIn: Bool) -> Bool {
    isSignedIn
  }
}

private extension UIApplication {
  var foregroundWindowScene: UIWindowScene? {
    let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive }
      ?? scenes.first { $0.activationState == .foregroundInactive }
  }
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

struct SubscriptionScreenshotView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text("PumpSync Subscription")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(.primary)

        Text("Securely sync pump data to Apple Health without managing your own server.")
          .font(.title3)
          .foregroundStyle(Color.pumpSyncSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 16) {
        SubscriptionBenefitRow(
          title: "Managed connection",
          detail: "PumpSync operates and maintains the service for you.",
          systemImage: "server.rack"
        )

        SubscriptionBenefitRow(
          title: "Secure Health sync",
          detail: "Downloaded pump data is processed for sync and preview requests and is not kept on PumpSync servers.",
          systemImage: "heart.text.square"
        )

        SubscriptionBenefitRow(
          title: "No server setup",
          detail: "Sync without setting up or maintaining your own server.",
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

struct PumpSyncSubscriptionStoreView: View {
  @Environment(AppServices.self) private var services
  @Binding var isPresented: Bool
  var authServiceOverride: AuthService? = nil
  var onConnectionVerified: (() -> Void)? = nil
  var onConnectionAttemptFinished: (() -> Void)? = nil
  private var connectionAuth: AuthService { authServiceOverride ?? services.authService }
  @State private var purchaseAlert: ConnectionAlert?

  var body: some View {
    SubscriptionStoreView(productIDs: [AppConstants.subscriptionProductId]) {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text("PumpSync Subscription")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)

          Text("Subscribe to securely sync pump data to Apple Health without managing your own server.")
            .font(.title3)
            .foregroundStyle(Color.pumpSyncSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 12) {
          SubscriptionBenefitRow(
            title: "Managed connection",
            detail: "PumpSync operates and maintains the service for you.",
            systemImage: "server.rack"
          )

          SubscriptionBenefitRow(
            title: "Secure Health sync",
            detail: "Downloaded pump data is processed for sync and preview requests and is not kept on PumpSync servers.",
            systemImage: "heart.text.square"
          )

          SubscriptionBenefitRow(
            title: "No server setup",
            detail: "Sync without setting up or maintaining your own server.",
            systemImage: "checkmark.shield"
          )
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.top, 24)
    }
    .subscriptionStoreButtonLabel(.action)
    // App Review guideline 3.1.2 requires functional Terms of Use and Privacy
    // Policy links on the purchase screen for auto-renewable subscriptions.
    .subscriptionStorePolicyDestination(url: AppConstants.termsOfUseURL, for: .termsOfService)
    .subscriptionStorePolicyDestination(url: AppConstants.privacyPolicyURL, for: .privacyPolicy)
    .onInAppPurchaseCompletion { _, result in
      await handlePurchaseCompletion(result)
    }
    .alert(
      purchaseAlert?.title ?? "",
      isPresented: Binding(
        get: { purchaseAlert != nil },
        set: { isPresented in
          if !isPresented {
            purchaseAlert = nil
          }
        }
      ),
      presenting: purchaseAlert
    ) { alert in
      switch alert.action {
      case .manageSubscription:
        Button("Manage Subscription") {
          Task {
            await presentManageSubscriptions()
          }
        }
        Button("OK", role: .cancel) {}
      case nil:
        Button("OK", role: .cancel) {}
      }
    } message: { alert in
      Text(alert.message)
    }
  }

  private func handlePurchaseCompletion(_ result: Result<Product.PurchaseResult, Error>) async {
    defer { onConnectionAttemptFinished?() }
    switch result {
    case .success(.success(let verificationResult)):
      do {
        let transaction = try verified(verificationResult)
        guard transaction.isActiveSubscriptionEntitlement else {
          services.diagnosticsLogStore.record(
            source: .auth,
            severity: .warning,
            title: "Inactive subscription transaction returned",
            message: transaction.diagnosticSummary(active: false)
          )
          await transaction.finish()
          purchaseAlert = ConnectionAlert(
            title: "Subscription Inactive",
            message: "This subscription is inactive. Manage your Apple subscription, then return to PumpSync and tap Restore Subscription.",
            action: .manageSubscription
          )
          return
        }

        services.diagnosticsLogStore.record(
          source: .auth,
          title: "Active subscription transaction returned",
          message: transaction.diagnosticSummary(active: true)
        )
        await transaction.finish()
        await connectionAuth.activateSubscription(entitlement: try VerifiedSubscriptionEntitlement.verified(verificationResult))
        if connectionAuth.isSignedIn {
          onConnectionVerified?()
          isPresented = false
        } else {
          purchaseAlert = ConnectionAlert(
            title: "Subscription Verification Failed",
            message: connectionAuth.connectionRequiredMessage
          )
        }
      } catch {
        connectionAuth.recordSubscriptionPurchaseFailed(error)
        purchaseAlert = ConnectionAlert(
          title: "Subscription Verification Failed",
          message: connectionAuth.connectionRequiredMessage
        )
      }
    case .success(.userCancelled):
      connectionAuth.recordSubscriptionPurchaseCancelled()
    case .success(.pending):
      connectionAuth.recordSubscriptionPurchasePending()
      purchaseAlert = ConnectionAlert(
        title: "Subscription Pending",
        message: connectionAuth.statusMessage
      )
    case .failure(let error):
      connectionAuth.recordSubscriptionPurchaseFailed(error)
      purchaseAlert = ConnectionAlert(
        title: "Subscription Failed",
        message: connectionAuth.connectionRequiredMessage
      )
    @unknown default:
      connectionAuth.recordSubscriptionPurchaseFailed(StoreKitSubscriptionError.unverifiedTransaction)
      purchaseAlert = ConnectionAlert(
        title: "Subscription Failed",
        message: connectionAuth.connectionRequiredMessage
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

  private func presentManageSubscriptions() async {
    defer { onConnectionAttemptFinished?() }
    guard let scene = UIApplication.shared.foregroundWindowScene else {
      let error = StoreKitSubscriptionError.subscriptionManagementUnavailable
      services.diagnosticsLogStore.record(error: error, source: .auth, title: "Manage subscription failed")
      purchaseAlert = ConnectionAlert(
        title: "Manage Subscription Unavailable",
        message: "PumpSync could not open Apple subscription management. Try again from the Settings app."
      )
      return
    }

    do {
      try await AppStore.showManageSubscriptions(in: scene, subscriptionGroupID: AppConstants.subscriptionGroupId)
      await connectionAuth.recoverSessionIfNeeded()
      if SubscriptionPresentation.shouldDismissAfterManageSubscriptions(isSignedIn: connectionAuth.isSignedIn) {
        onConnectionVerified?()
        isPresented = false
      }
    } catch {
      services.diagnosticsLogStore.record(error: error, source: .auth, title: "Manage subscription failed")
      purchaseAlert = ConnectionAlert(
        title: "Manage Subscription Failed",
        message: "PumpSync could not open Apple subscription management. Try again from the Settings app."
      )
    }
  }
}

private struct SubscriptionBenefitRow: View {
  let title: String
  let detail: String
  let systemImage: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.blue)
        .fixedSize()
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(detail)
          .font(.subheadline)
          .foregroundStyle(Color.pumpSyncSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(detail)
  }
}
