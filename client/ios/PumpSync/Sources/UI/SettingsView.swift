import SwiftUI

struct SettingsView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    PumpSyncScreen(spacing: 10) {
      GlassSection("Account") {
        if services.authService.isSignedIn {
          GlassStatusRow(
            title: "Apple account",
            value: services.authService.statusMessage,
            systemImage: "checkmark.seal.fill",
            tint: .green
          )

          GlassDivider()

          Button(role: .destructive) {
            services.authService.signOut()
          } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.glass)
        } else {
          VStack(alignment: .leading, spacing: 12) {
            SignInWithAppleButton(isEnabled: !services.authService.isSigningIn) {
              Task {
                await services.authService.signIn()
              }
            }
            .frame(height: 52)
            .accessibilityIdentifier("settings.signInWithAppleButton")

            HStack(spacing: 8) {
              if services.authService.isSigningIn {
                ProgressView()
              }

              Text(services.authService.errorMessage ?? services.authService.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      GlassSection("PumpSync") {
        NavigationLink {
          TandemCredentialForm()
        } label: {
          GlassNavigationRow("Credentials", subtitle: services.credentialStore.hasStoredCredentials ? "Saved on this device" : "Not configured", systemImage: "key")
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
          GlassNavigationRow("Apple Health Access", subtitle: services.healthKitService.isAuthorized ? "Write access allowed" : "Review write access", systemImage: "heart")
        }
        .buttonStyle(.plain)

        GlassDivider()

        NavigationLink {
          PrivacyView()
        } label: {
          GlassNavigationRow("Data Handling", systemImage: "lock.shield")
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
}
