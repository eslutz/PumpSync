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
          Button {
            Task {
              await services.authService.signIn()
            }
          } label: {
            Label("Sign in with Apple", systemImage: "apple.logo")
          }
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
