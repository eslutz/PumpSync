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

        GlassDivider()

        GlassStatusRow(
          title: "Session",
          value: services.authService.isSignedIn
            ? services.authService.statusMessage
            : services.authService.errorMessage ?? services.authService.statusMessage,
          systemImage: services.authService.isSignedIn ? "checkmark.seal.fill" : "network.badge.shield.half.filled",
          tint: services.authService.isSignedIn ? .green : .secondary
        )

        switch services.backendConfigurationStore.mode {
        case .hosted:
          GlassDivider()

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
          GlassDivider()

          TextField("https://example.com/api", text: selfHostedURLBinding)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            .frame(minHeight: 44)

          GlassDivider()

          Button {
            Task {
              await services.authService.connectSelfHosted()
            }
          } label: {
            GlassPrimaryLabel(
              title: services.authService.isConnecting ? "Connecting" : "Connect",
              systemImage: "server.rack"
            )
          }
          .buttonStyle(GroupedRowActionButtonStyle())
          .disabled(services.authService.isConnecting)
        }

        if services.authService.isConnecting {
          GlassDivider()

          HStack(spacing: 8) {
            ProgressView()
            Text(services.authService.statusMessage)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        if services.authService.isSignedIn {
          GlassDivider()

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
          GlassNavigationRow("Credentials", subtitle: tandemCredentialStatus, systemImage: "key")
        }
        .buttonStyle(.plain)

        if let redactedUsername = services.credentialStore.redactedUsername {
          GlassDivider()

          GlassStatusRow(title: "Stored account", value: redactedUsername, systemImage: "person.text.rectangle")
        }

        GlassDivider()

        NavigationLink {
          HealthAccessView()
        } label: {
          GlassNavigationRow("Apple Health Access", subtitle: healthWriteStatus, systemImage: "heart")
        }
        .buttonStyle(.plain)

        GlassDivider()

        NavigationLink {
          PrivacyView()
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

  private var healthWriteStatus: String {
    if services.healthKitService.isAuthorized {
      return "Write access allowed"
    }

    if services.healthKitService.hasAnyWritePermission {
      return "Partial write access allowed"
    }

    return "Review write access"
  }
}
