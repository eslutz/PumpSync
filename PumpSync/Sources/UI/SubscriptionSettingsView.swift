import StoreKit
import SwiftUI

struct SubscriptionSettingsView: View {
  @Environment(AppServices.self) private var services
  @State private var purchaseRequest: SubscriptionConnectionRequest?
  @State private var showsManagement = false
  @State private var isRestoring = false
  @State private var restoreMessage: String?

  var body: some View {
    SubscriptionSettingsContent(
      status: services.authService.subscriptionAccessStatus,
      isRestoring: isRestoring,
      isConnecting: services.connectionSettings.isConnecting,
      needsConnection: services.connectionSettings.mode == .hosted
        && (services.connectionSettings.hasChanges || !services.authService.isSignedIn),
      canActivate: services.connectionSettings.mode == .hosted && services.connectionSettings.canConnect,
      canRestore: services.connectionSettings.mode == .selfHosted || services.connectionSettings.canConnect,
      message: restoreMessage,
      manage: { showsManagement = true },
      connect: connect,
      subscribe: { purchaseRequest = services.connectionSettings.prepareSubscription() },
      restore: restore
    )
    .manageSubscriptionsSheet(isPresented: $showsManagement, subscriptionGroupID: AppConstants.subscriptionGroupId)
    .onChange(of: showsManagement) { _, presented in
      if !presented {
        Task { await services.authService.refreshSubscriptionStatus() }
      }
    }
    .sheet(item: $purchaseRequest) { request in
      Group {
#if DEBUG
        if AppLaunchEnvironment.isScreenshotMode { SubscriptionScreenshotView() }
        else { store(request) }
#else
        store(request)
#endif
      }
      .onDisappear { services.connectionSettings.finishSubscription(request, verified: false) }
    }
    .task {
      if !AppLaunchEnvironment.isScreenshotMode {
        await services.authService.refreshSubscriptionStatus()
      }
    }
  }

  private func store(_ request: SubscriptionConnectionRequest) -> some View {
    PumpSyncSubscriptionStoreView(
      isPresented: Binding(get: { purchaseRequest?.id == request.id }, set: {
        if !$0 && purchaseRequest?.id == request.id { purchaseRequest = nil }
      }),
      authServiceOverride: request.auth,
      onConnectionVerified: { services.connectionSettings.finishSubscription(request, verified: true) },
      onConnectionAttemptFinished: { services.connectionSettings.subscriptionAttemptFinished(request) }
    )
  }

  private func restore() {
    guard !isRestoring,
      services.connectionSettings.mode == .selfHosted || services.connectionSettings.canConnect else { return }
    restoreMessage = nil
    isRestoring = true
    // ConnectionSettingsController owns hosted connection cancellation, so
    // returning to Settings keeps its Cancel Changes action effective.
    Task {
      defer { isRestoring = false }
      if services.connectionSettings.mode == .hosted {
        await services.connectionSettings.connect()
        await services.authService.refreshSubscriptionStatus()
        restoreMessage = services.connectionSettings.connectionDescription
      } else {
        // Subscription recovery must not replace an intentionally self-hosted connection.
        switch await services.authService.restoreSubscriptionAccess() {
        case .restored:
          restoreMessage = "Your subscription is active. Your self-hosted connection is unchanged."
        case .noActiveSubscription:
          restoreMessage = "No active subscription was found. Your self-hosted connection is unchanged."
        case .cancelled:
          restoreMessage = "Restoration canceled. Your connection is unchanged."
        case .appStoreUnavailable, .backendVerificationFailed:
          restoreMessage = "Your subscription could not be restored. Try again when the App Store is available."
        }
      }
    }
  }

  private func connect() {
    restoreMessage = nil
    Task {
      await services.connectionSettings.connect(restorePurchases: false)
      await services.authService.refreshSubscriptionStatus()
      restoreMessage = services.connectionSettings.connectionDescription
    }
  }
}

private struct SubscriptionSettingsContent: View {
  let status: SubscriptionAccessStatus
  let isRestoring: Bool
  let isConnecting: Bool
  let needsConnection: Bool
  let canActivate: Bool
  let canRestore: Bool
  let message: String?
  let manage: () -> Void
  let connect: () -> Void
  let subscribe: () -> Void
  let restore: () -> Void

  var body: some View {
    Form {
      Section {
        LabeledContent("Status") { Text(status.title).foregroundStyle(Color.primary) }
        Button(action: manage) {
          Text("Manage Subscription")
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
          .disabled(isRestoring || isConnecting)
          .accessibilityIdentifier("ManageSubscriptionButton")
        if needsConnection && status == .active {
          Button(isConnecting && !isRestoring ? "Connecting" : "Connect PumpSync", systemImage: "link", action: connect)
            .buttonStyle(.glassProminent)
            .tint(Color("ProminentActionColor"))
            .controlSize(.large)
            .disabled(!canActivate || isRestoring)
            .accessibilityIdentifier("ConnectSubscriptionButton")
        }
        if status != .active {
          Button("Subscription Options", systemImage: "cart", action: subscribe)
            .disabled(!canActivate || isRestoring)
        }
      } footer: {
        Text("Manage your plan, renewal, or cancellation through Apple. Changing connection mode does not cancel your subscription.")
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Section {
        Button(action: restore) {
          if isRestoring {
            HStack {
              ProgressView()
              Text("Restoring Purchases")
            }
          } else {
            Label("Restore Purchases", systemImage: "arrow.clockwise")
          }
        }
        .disabled(isRestoring || !canRestore)
        .accessibilityIdentifier("RestorePurchasesButton")
        if let message {
          Text(message)
            .accessibilityIdentifier("SubscriptionRestoreFeedback")
        }
      } footer: {
        Text("If an existing purchase is not recognized, restore it to recheck access with Apple. Restoring does not buy or renew a subscription.")
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .navigationTitle("Subscription")
    .navigationBarTitleDisplayMode(.inline)
  }
}

extension SubscriptionAccessStatus {
  var title: String {
    switch self {
    case .unknown: String(localized: "Not checked")
    case .active: String(localized: "Active")
    case .inactive: String(localized: "Not active")
    case .unavailable: String(localized: "Unable to verify")
    }
  }
}

#if DEBUG
#Preview("Active subscription") {
  NavigationStack {
    SubscriptionSettingsContent(status: .active, isRestoring: false, isConnecting: false, needsConnection: false,
      canActivate: true, canRestore: true, message: nil, manage: {}, connect: {}, subscribe: {}, restore: {})
  }
}

#Preview("Subscription not recognized") {
  NavigationStack {
    SubscriptionSettingsContent(status: .inactive, isRestoring: false, isConnecting: false, needsConnection: true,
      canActivate: true, canRestore: true, message: "No active subscription was found.", manage: {}, connect: {}, subscribe: {}, restore: {})
  }
}
#endif
