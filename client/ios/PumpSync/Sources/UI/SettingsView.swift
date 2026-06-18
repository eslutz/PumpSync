import SwiftUI

struct SettingsView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    List {
      Section("Account") {
        if services.authService.isSignedIn {
          Button(role: .destructive) {
            services.authService.signOut()
          } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
          }
        } else {
          SignInWithAppleButton(isEnabled: !services.authService.isSigningIn) {
            Task {
              await services.authService.signIn()
            }
          }
          .frame(height: 52)
          .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
          .accessibilityIdentifier("settings.signInWithAppleButton")
        }

        HStack(spacing: 8) {
          if services.authService.isSigningIn {
            ProgressView()
          }

          Text(services.authService.statusMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if let message = services.authService.errorMessage {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }

      Section("Tandem") {
        NavigationLink {
          TandemCredentialForm()
        } label: {
          Label("Credentials", systemImage: "key")
        }

        if let redactedUsername = services.credentialStore.redactedUsername {
          LabeledContent("Stored account", value: redactedUsername)
        }
      }

      Section("Apple Health") {
        Button {
          Task {
            do {
              try await services.healthKitService.requestAuthorization()
            } catch {
              services.healthKitService.errorMessage = error.localizedDescription
            }
          }
        } label: {
          Label("Authorize Health Writes", systemImage: "heart")
        }

        if let message = services.healthKitService.errorMessage {
          Text(message)
            .foregroundStyle(.secondary)
        }
      }

      Section("Privacy") {
        NavigationLink {
          PrivacyView()
        } label: {
          Label("Data Handling", systemImage: "lock.shield")
        }
      }
    }
    .navigationTitle("Settings")
  }
}
