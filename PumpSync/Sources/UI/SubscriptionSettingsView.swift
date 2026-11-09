import StoreKit
import SwiftUI

struct SubscriptionSettingsView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.editingScreenDepartureID) private var editingScreenDepartureID
  @State private var connection: ConnectionSettingsController?
  @State private var purchaseRequest: SubscriptionConnectionRequest?
  @State private var presentedPurchaseRequest: SubscriptionConnectionRequest?
  @State private var showsManagement = false
  @State private var isRestoring = false
  @State private var restoreMessage: String?
  @State private var operation: Task<Void, Never>?
  @State private var operationID = UUID()
  @State private var managementID: UUID?

  var body: some View {
    SubscriptionSettingsContent(
      status: services.authService.subscriptionAccessStatus,
      isRestoring: isRestoring,
      isConnecting: connection?.isConnecting == true,
      needsConnection: services.backendConfigurationStore.mode != .hosted || !services.authService.isSignedIn,
      canActivate: connection?.canConnect == true,
      canRestore: connection?.committedMode == .selfHosted || connection?.canConnect == true,
      message: restoreMessage,
      manage: { managementID = operationID; showsManagement = true },
      connect: connect,
      subscribe: subscribe,
      restore: restore
    )
    .onAppear {
      if connection == nil { connection = services.connectionSettings.independentController() }
    }
    .onDisappear {
      // Apple's sheets continue the current explicit action. Navigating to
      // another app screen instead invalidates this screen's work.
      if purchaseRequest == nil && !showsManagement { discardDraft() }
    }
    .onChange(of: editingScreenDepartureID) { _, _ in discardDraft() }
    .manageSubscriptionsSheet(isPresented: $showsManagement, subscriptionGroupID: AppConstants.subscriptionGroupId)
    .onChange(of: showsManagement) { _, presented in
      if !presented {
        let isCurrent = managementID == operationID
        managementID = nil
        if isCurrent { refreshSubscriptionStatus() }
      }
    }
    .sheet(item: $purchaseRequest, onDismiss: purchaseSheetDidDismiss) { request in
      Group {
#if DEBUG
        if AppLaunchEnvironment.isScreenshotMode { SubscriptionScreenshotView() }
        else { store(request) }
#else
        store(request)
#endif
      }
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
      onConnectionVerified: { connection?.finishSubscription(request, verified: true) },
      onConnectionAttemptFinished: { connection?.subscriptionAttemptFinished(request) },
      isConnectionRequestCurrent: { connection?.isCurrentSubscriptionRequest(request) == true },
      connectionFailureMessage: { connection?.connectionDescription ?? "Connect PumpSync to use your subscription." }
    )
  }

  private func subscribe() {
    guard presentedPurchaseRequest == nil, let connection, connection.canConnect else { return }
    connection.mode = .hosted
    let request = connection.prepareSubscription()
    presentedPurchaseRequest = request
    purchaseRequest = request
  }

  private func purchaseSheetDidDismiss() {
    // The retained identity belongs to this presentation, including while
    // Apple's management UI temporarily covers its content. A new purchase
    // cannot replace it before the sheet's dismissal has completed.
    guard let request = presentedPurchaseRequest else { return }
    presentedPurchaseRequest = nil
    guard connection?.isCurrentSubscriptionRequest(request) == true else { return }
    connection?.finishSubscription(request, verified: false)
  }

  private func restore() {
    guard let connection, !isRestoring,
      connection.committedMode == .selfHosted || connection.canConnect else { return }
    operation?.cancel()
    let submitted = UUID()
    operationID = submitted
    restoreMessage = nil
    isRestoring = true
    let restoresHostedConnection = connection.committedMode == .hosted
    operation = Task {
      defer {
        if operationID == submitted { isRestoring = false; operation = nil }
      }
      if restoresHostedConnection {
        connection.mode = .hosted
        await connection.connect()
        guard !Task.isCancelled, operationID == submitted else { return }
        await services.authService.refreshSubscriptionStatus()
        guard !Task.isCancelled, operationID == submitted else { return }
        restoreMessage = connection.connectionDescription
      } else {
        // Restore access for the committed service; a discarded Settings
        // picker selection must never replace a self-hosted connection.
        let result = await services.authService.restoreSubscriptionAccess()
        guard !Task.isCancelled, operationID == submitted else { return }
        switch result {
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
    guard let connection, connection.canConnect else { return }
    operation?.cancel()
    let submitted = UUID()
    operationID = submitted
    restoreMessage = nil
    connection.mode = .hosted
    operation = Task {
      defer { if operationID == submitted { operation = nil } }
      await connection.connect(restorePurchases: false)
      guard !Task.isCancelled, operationID == submitted else { return }
      await services.authService.refreshSubscriptionStatus()
      guard !Task.isCancelled, operationID == submitted else { return }
      restoreMessage = connection.connectionDescription
    }
  }

  private func refreshSubscriptionStatus() {
    operation?.cancel()
    operation = Task { await services.authService.refreshSubscriptionStatus() }
  }

  private func discardDraft() {
    managementID = nil
    operationID = UUID()
    operation?.cancel()
    operation = nil
    connection?.cancel()
    purchaseRequest = nil
    isRestoring = false
    restoreMessage = nil
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
