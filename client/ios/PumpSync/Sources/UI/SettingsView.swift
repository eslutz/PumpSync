import SwiftUI

struct SettingsView: View {
  @Environment(AppServices.self) private var services

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
            Task {
              await services.authService.purchaseHostedSubscription()
            }
          } label: {
            GlassPrimaryLabel(
              title: services.authService.isConnecting ? "Connecting" : "Subscribe",
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
