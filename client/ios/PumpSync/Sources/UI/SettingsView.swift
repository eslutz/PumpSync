import StoreKit
import SwiftUI

struct SettingsView: View {
  @Environment(AppServices.self) private var services
  @State private var isShowingHostedSubscriptionStore = false

  var body: some View {
    PumpSyncScreen(spacing: 10) {
      GlassSection("Connection") {
        Picker("Mode", selection: backendModeBinding) {
          ForEach(BackendAccessMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)

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
          .disabled(services.authService.isConnecting)

          Button {
            Task {
              await services.authService.connectHostedUsingCurrentSubscription()
            }
          } label: {
            Label("Restore Subscription", systemImage: "arrow.clockwise")
              .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
          }
          .buttonStyle(GroupedInlineButtonStyle())
          .disabled(services.authService.isConnecting)

        case .selfHosted:
          Text("Use your own PumpSync-compatible server to sync pump data to Apple Health. You manage hosting, security, and maintenance.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)

          VStack(alignment: .leading, spacing: 6) {
            Text("Server URL")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)

            TextField("https://example.com/api", text: selfHostedURLBinding)
              .textInputAutocapitalization(.never)
              .keyboardType(.URL)
              .autocorrectionDisabled()
              .frame(minHeight: 44)
          }

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
        }

        if services.authService.isConnecting {
          HStack(spacing: 8) {
            ProgressView()
            Text(services.authService.statusMessage)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        if services.authService.isSignedIn {
          Button(role: .destructive) {
            services.authService.signOut()
          } label: {
            Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(GroupedInlineButtonStyle())
        }
      }

      GlassSection("PumpSync") {
        NavigationLink {
          TandemCredentialForm()
        } label: {
          GlassNavigationRow("Tandem Account", subtitle: tandemAccountStatus, systemImage: "key")
        }
        .buttonStyle(.plain)

        GlassDivider()

        NavigationLink {
          HealthAccessView()
        } label: {
          GlassNavigationRow("Apple Health", subtitle: "Insulin and carbohydrates", systemImage: "heart")
        }
        .buttonStyle(.plain)

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

        GlassDivider()

        NavigationLink {
          DeveloperView()
        } label: {
          GlassNavigationRow("Developer", subtitle: "Diagnostics, build, and sync details", systemImage: "hammer")
        }
        .buttonStyle(.plain)
      }
    }
    .navigationTitle("Settings")
    .sheet(isPresented: $isShowingHostedSubscriptionStore) {
      HostedSubscriptionStoreView(isPresented: $isShowingHostedSubscriptionStore)
    }
  }

  private var backendModeBinding: Binding<BackendAccessMode> {
    Binding(
      get: {
        services.backendConfigurationStore.mode
      },
      set: { mode in
        services.backendConfigurationStore.mode = mode
        services.authService.signOut()
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
          services.authService.signOut()
          _ = services.backendConfigurationStore.apply(to: services.apiClient)
        }
      }
    )
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

    return "\(redactedUsername) - \(tandemCredentialStatus)"
  }

}

private struct HostedSubscriptionStoreView: View {
  @Environment(AppServices.self) private var services
  @Binding var isPresented: Bool

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
            detail: "Pump data syncs to Apple Health during active sync operations.",
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
        }
      } catch {
        services.authService.recordHostedSubscriptionPurchaseFailed(error)
      }
    case .success(.userCancelled):
      services.authService.recordHostedSubscriptionPurchaseCancelled()
    case .success(.pending):
      services.authService.recordHostedSubscriptionPurchasePending()
    case .failure(let error):
      services.authService.recordHostedSubscriptionPurchaseFailed(error)
    @unknown default:
      services.authService.recordHostedSubscriptionPurchaseFailed(StoreKitSubscriptionError.unverifiedTransaction)
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
  }
}
