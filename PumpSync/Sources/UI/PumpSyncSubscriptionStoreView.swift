import StoreKit
import SwiftUI
import UIKit

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

struct SubscriptionScreenshotView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text("PumpSync Subscription")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(.primary)

        Text("Securely sync pump data to Apple Health without managing your own server.")
          .font(.title3)
          .foregroundStyle(.secondary)
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
      .tint(Color("ProminentActionColor"))
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
  var isConnectionRequestCurrent: () -> Bool = { true }
  var connectionFailureMessage: (() -> String)? = nil
  private var connectionAuth: AuthService { authServiceOverride ?? services.authService }
  @State private var purchaseAlert: ConnectionAlert?
  @State private var deliveryTask: Task<Void, Never>?
  @State private var deliveryID: UUID?
  @State private var managementTask: Task<Void, Never>?
  @State private var managementID: UUID?
  @State private var isManagingSubscription = false

  var body: some View {
    SubscriptionStoreView(productIDs: [AppConstants.subscriptionProductId]) {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text("PumpSync Subscription")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.primary)

          Text("Subscribe to securely sync pump data to Apple Health without managing your own server.")
            .font(.title3)
            .foregroundStyle(.secondary)
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
    .tint(Color("ProminentActionColor"))
    .subscriptionStoreButtonLabel(.action)
    .subscriptionStorePolicyForegroundStyle(Color.accentColor)
    .storeButton(.hidden, for: .restorePurchases)
    // App Review guideline 3.1.2 requires functional Terms of Use and Privacy
    // Policy links on the purchase screen for auto-renewable subscriptions.
    .subscriptionStorePolicyDestination(url: AppConstants.termsOfUseURL, for: .termsOfService)
    .subscriptionStorePolicyDestination(url: AppConstants.privacyPolicyURL, for: .privacyPolicy)
    .onInAppPurchaseCompletion { _, result in
      let submitted = UUID()
      deliveryID = submitted
      deliveryTask?.cancel()
      let task = Task { await handlePurchaseCompletion(result) }
      deliveryTask = task
      await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
      if deliveryID == submitted { deliveryTask = nil; deliveryID = nil }
    }
    .onDisappear {
      if !isManagingSubscription {
        deliveryTask?.cancel()
        managementTask?.cancel()
      }
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
        Button("Manage Subscription", action: startSubscriptionManagement)
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
    guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
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
          guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
          purchaseAlert = ConnectionAlert(
            title: "Subscription Inactive",
            message: "This subscription is inactive. Manage your Apple subscription, then return to PumpSync and tap Restore Purchases.",
            action: .manageSubscription
          )
          return
        }

        services.diagnosticsLogStore.record(
          source: .auth,
          title: "Active subscription transaction returned",
          message: transaction.diagnosticSummary(active: true)
        )
        let entitlement = try VerifiedSubscriptionEntitlement.verified(verificationResult)
        // StoreKit retains an unfinished verified transaction for delivery.
        // Leaving this editor must not start a new connection from its draft.
        guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
        await connectionAuth.activateSubscription(entitlement: entitlement)
        guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
        if connectionAuth.errorMessage == nil && connectionAuth.canFinishSubscriptionDelivery(entitlement: entitlement) {
          onConnectionVerified?()
          if services.authService.canFinishSubscriptionDelivery(entitlement: entitlement) {
            await transaction.finish()
            guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
            await services.authService.refreshSubscriptionStatus()
            guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
            isPresented = false
          } else {
            purchaseAlert = ConnectionAlert(
              title: "Connection Activation Failed",
              message: connectionFailureMessage?() ?? connectionAuth.connectionRequiredMessage
            )
          }
        } else {
          purchaseAlert = ConnectionAlert(
            title: "Subscription Verification Failed",
            message: connectionAuth.connectionRequiredMessage
          )
        }
      } catch {
        guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
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
    guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
    isManagingSubscription = true
    defer { isManagingSubscription = false; onConnectionAttemptFinished?() }
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
      // Only Apple's presented UI is a continuation that can cover this view.
      // Once it closes, leaving the purchase page must cancel recovery work.
      isManagingSubscription = false
      guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
      await connectionAuth.recoverSessionIfNeeded()
      guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
      if SubscriptionPresentation.shouldDismissAfterManageSubscriptions(isSignedIn: connectionAuth.isSignedIn) {
        onConnectionVerified?()
        isPresented = false
      }
    } catch {
      guard !Task.isCancelled, isConnectionRequestCurrent() else { return }
      services.diagnosticsLogStore.record(error: error, source: .auth, title: "Manage subscription failed")
      purchaseAlert = ConnectionAlert(
        title: "Manage Subscription Failed",
        message: "PumpSync could not open Apple subscription management. Try again from the Settings app."
      )
    }
  }

  private func startSubscriptionManagement() {
    managementTask?.cancel()
    let submitted = UUID()
    managementID = submitted
    managementTask = Task {
      await presentManageSubscriptions()
      guard managementID == submitted else { return }
      managementTask = nil
      managementID = nil
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
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(detail)
  }
}
