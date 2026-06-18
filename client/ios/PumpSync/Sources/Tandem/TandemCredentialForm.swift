import SwiftUI

struct TandemCredentialForm: View {
  @Environment(AppServices.self) private var services

  @State private var username = ""
  @State private var password = ""
  @State private var region = TandemRegion.us
  @State private var message: String?
  @State private var isShowingPassword = false
  @State private var isValidating = false
  @State private var validatedCredentials: TandemCredentials?

  var body: some View {
    PumpSyncScreen {
      GlassSection("Tandem Source") {
        TextField("Username", text: $username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .frame(minHeight: 44)

        GlassDivider()

        if isShowingPassword {
          TextField("Password", text: $password)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: 44)
        } else {
          SecureField("Password", text: $password)
            .textContentType(.password)
            .frame(minHeight: 44)
        }

        GlassDivider()

        Toggle("Show password", isOn: $isShowingPassword)
          .frame(minHeight: 44)

        GlassDivider()

        Picker("Region", selection: $region) {
          ForEach(TandemRegion.allCases) { region in
            Text(region.title).tag(region)
          }
        }
        .frame(minHeight: 44)
      }

      Button {
        Task {
          await validateConnection()
        }
      } label: {
        GlassPrimaryLabel(title: isValidating ? "Validating" : "Validate Connection", systemImage: "checkmark.shield")
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canValidate)

      Button {
        save()
      } label: {
        GlassPrimaryLabel(title: "Save Credentials", systemImage: "key.fill")
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canSave)

      Button(role: .destructive) {
        delete()
      } label: {
        Label("Remove Credentials", systemImage: "trash")
          .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!services.credentialStore.hasStoredCredentials)

      if let message {
        GlassSection {
          Text(message)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Tandem")
    .onAppear(perform: load)
    .onChange(of: username) { _, _ in
      clearValidationIfNeeded()
    }
    .onChange(of: password) { _, _ in
      clearValidationIfNeeded()
    }
    .onChange(of: region) { _, _ in
      clearValidationIfNeeded()
    }
  }

  private var currentCredentials: TandemCredentials {
    TandemCredentials(
      username: username.trimmingCharacters(in: .whitespacesAndNewlines),
      password: password,
      region: region.rawValue
    )
  }

  private var hasRequiredFields: Bool {
    !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
  }

  private var validationMatchesCurrentInput: Bool {
    validatedCredentials == currentCredentials
  }

  private var canValidate: Bool {
    hasRequiredFields && services.authService.isSignedIn && !isValidating
  }

  private var canSave: Bool {
    hasRequiredFields && validationMatchesCurrentInput && !isValidating
  }

  private func load() {
    do {
      guard let credentials = try services.credentialStore.load() else {
        return
      }

      username = credentials.username
      password = credentials.password
      region = TandemRegion(rawValue: credentials.region) ?? .us
      if services.credentialStore.hasValidatedCredentials {
        validatedCredentials = credentials
      }
    } catch {
      services.diagnosticsLogStore.record(source: .credential, severity: .error, title: "Credentials unavailable", message: error.localizedDescription)
    }
  }

  private func validateConnection() async {
    guard let accessToken = services.authService.accessToken else {
      message = "Connect backend access before validating Tandem credentials."
      return
    }

    isValidating = true
    message = "Validating Tandem credentials..."

    do {
      let credentials = currentCredentials
      let response = try await services.apiClient.validateTandemCredentials(
        TandemCredentialValidationRequest(tandem: credentials),
        accessToken: accessToken
      )

      guard response.validated else {
        validatedCredentials = nil
        message = "Tandem credentials could not be validated. Check the account details and try again."
        services.diagnosticsLogStore.record(source: .credential, severity: .warning, title: "Credentials validation rejected")
        isValidating = false
        return
      }

      validatedCredentials = credentials
      message = "Tandem credentials validated. Save them to this device to enable syncing."
      services.diagnosticsLogStore.record(source: .credential, title: "Credentials validated")
    } catch {
      validatedCredentials = nil
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials validation failed")
      message = "Tandem credentials could not be validated. Check the account details and try again."
    }

    isValidating = false
  }

  private func save() {
    do {
      guard validationMatchesCurrentInput else {
        message = "Validate the Tandem connection before saving credentials."
        return
      }

      try services.credentialStore.saveValidated(currentCredentials)
      message = "Validated Tandem credentials saved to this device."
    } catch {
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials save failed")
      message = "Tandem credentials could not be saved. Please try again."
    }
  }

  private func delete() {
    do {
      try services.credentialStore.delete()
      username = ""
      password = ""
      validatedCredentials = nil
      message = "Tandem credentials removed from this device."
    } catch {
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials removal failed")
      message = "Tandem credentials could not be removed. Please try again."
    }
  }

  private func clearValidationIfNeeded() {
    if validatedCredentials != currentCredentials {
      validatedCredentials = nil
    }
  }
}
