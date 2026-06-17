import SwiftUI

struct TandemCredentialForm: View {
  @Environment(AppServices.self) private var services

  @State private var username = ""
  @State private var password = ""
  @State private var region = TandemRegion.us
  @State private var message: String?
  @State private var isShowingPassword = false

  var body: some View {
    Form {
      Section("Tandem Source") {
        TextField("Username", text: $username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()

        if isShowingPassword {
          TextField("Password", text: $password)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } else {
          SecureField("Password", text: $password)
            .textContentType(.password)
        }

        Toggle("Show password", isOn: $isShowingPassword)

        Picker("Region", selection: $region) {
          ForEach(TandemRegion.allCases) { region in
            Text(region.title).tag(region)
          }
        }
      }

      Section {
        Button {
          save()
        } label: {
          Label("Save Credentials", systemImage: "key.fill")
        }
        .disabled(username.isEmpty || password.isEmpty)

        Button(role: .destructive) {
          delete()
        } label: {
          Label("Remove Credentials", systemImage: "trash")
        }
        .disabled(!services.credentialStore.hasStoredCredentials)
      }

      if let message {
        Section {
          Text(message)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Tandem")
    .onAppear(perform: load)
  }

  private func load() {
    do {
      guard let credentials = try services.credentialStore.load() else {
        return
      }

      username = credentials.username
      password = credentials.password
      region = TandemRegion(rawValue: credentials.region) ?? .us
    } catch {
      message = error.localizedDescription
    }
  }

  private func save() {
    do {
      try services.credentialStore.save(
        TandemCredentials(
          username: username,
          password: password,
          region: region.rawValue
        )
      )
      message = "Tandem credentials saved to this device."
    } catch {
      message = error.localizedDescription
    }
  }

  private func delete() {
    do {
      try services.credentialStore.delete()
      username = ""
      password = ""
      message = "Tandem credentials removed from this device."
    } catch {
      message = error.localizedDescription
    }
  }
}
