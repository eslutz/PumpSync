import SwiftUI

struct TandemCredentialForm: View {
  @Environment(AppServices.self) private var services

  @State private var username = ""
  @State private var password = ""
  @State private var region = TandemRegion.us
  @State private var alert: CredentialAlert?
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

        GlassDivider(leadingPadding: 0)

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

        GlassDivider(leadingPadding: 0)

        Toggle("Show password", isOn: $isShowingPassword)
          .frame(minHeight: 44)

        GlassDivider(leadingPadding: 0)

        HStack(spacing: 12) {
          Text("Region")
            .foregroundStyle(.primary)

          Spacer(minLength: 12)

          Picker("Region", selection: $region) {
            ForEach(TandemRegion.allCases) { region in
              Text(region.title).tag(region)
            }
          }
          .labelsHidden()
        }
        .frame(minHeight: 44)
      }

      Button {
        Task {
          if validationMatchesCurrentInput {
            save()
          } else {
            await validateConnection()
          }
        }
      } label: {
        GlassPrimaryLabel(title: primaryActionTitle, systemImage: primaryActionSystemImage)
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canUsePrimaryAction)

      Button(role: .destructive) {
        delete()
      } label: {
        GlassPrimaryLabel(title: "Remove Credentials", systemImage: "trash")
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!services.credentialStore.hasStoredCredentials)
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
    .alert(item: $alert) { alert in
      Alert(
        title: Text(alert.title),
        message: Text(alert.message),
        dismissButton: .default(Text("OK"))
      )
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
    hasRequiredFields && !isValidating && !services.authService.isConnecting
  }

  private var canSave: Bool {
    hasRequiredFields && validationMatchesCurrentInput && !isValidating && !services.authService.isConnecting
  }

  private var canUsePrimaryAction: Bool {
    validationMatchesCurrentInput ? canSave : canValidate
  }

  private var primaryActionTitle: String {
    if isValidating {
      return "Validating"
    }

    if services.authService.isConnecting {
      return "Connecting"
    }

    return validationMatchesCurrentInput ? "Save Credentials" : "Validate Connection"
  }

  private var primaryActionSystemImage: String {
    validationMatchesCurrentInput ? "key.fill" : "checkmark.shield"
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
    isValidating = true

    guard let accessToken = accessTokenForValidation() else {
      isValidating = false
      return
    }

    do {
      let credentials = currentCredentials
      let response = try await services.apiClient.validateTandemCredentials(
        TandemCredentialValidationRequest(tandem: credentials),
        accessToken: accessToken
      )

      guard response.validated else {
        validatedCredentials = nil
        alert = CredentialAlert(
          title: "Validation Failed",
          message: "Account details could not be validated. Check them and try again."
        )
        services.diagnosticsLogStore.record(source: .credential, severity: .warning, title: "Credentials validation rejected")
        isValidating = false
        return
      }

      validatedCredentials = credentials
      alert = CredentialAlert(
        title: "Connection Validated",
        message: "Account details validated. Save them to this device to enable syncing."
      )
      services.diagnosticsLogStore.record(source: .credential, title: "Credentials validated")
    } catch {
      validatedCredentials = nil
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials validation failed")
      alert = CredentialAlert(
        title: "Validation Failed",
        message: "Account details could not be validated. Check them and try again."
      )
    }

    isValidating = false
  }

  private func accessTokenForValidation() -> String? {
    if let accessToken = services.authService.accessToken {
      return accessToken
    }

    alert = CredentialAlert(
      title: "Connection Needed",
      message: services.authService.connectionRequiredMessage
    )
    return nil
  }

  private func save() {
    do {
      guard validationMatchesCurrentInput else {
        alert = CredentialAlert(
          title: "Validation Needed",
          message: "Validate the connection before saving credentials."
        )
        return
      }

      try services.credentialStore.saveValidated(currentCredentials)
      alert = CredentialAlert(
        title: "Credentials Saved",
        message: "Validated credentials saved to this device."
      )
    } catch {
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials save failed")
      alert = CredentialAlert(
        title: "Save Failed",
        message: "Credentials could not be saved. Please try again."
      )
    }
  }

  private func delete() {
    do {
      try services.credentialStore.delete()
      username = ""
      password = ""
      validatedCredentials = nil
      alert = CredentialAlert(
        title: "Credentials Removed",
        message: "Credentials removed from this device."
      )
    } catch {
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials removal failed")
      alert = CredentialAlert(
        title: "Remove Failed",
        message: "Credentials could not be removed. Please try again."
      )
    }
  }

  private func clearValidationIfNeeded() {
    if validatedCredentials != currentCredentials {
      validatedCredentials = nil
    }
  }
}

private struct CredentialAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
