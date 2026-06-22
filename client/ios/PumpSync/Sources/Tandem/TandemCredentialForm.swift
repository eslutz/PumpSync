import SwiftUI

struct TandemCredentialForm: View {
  @Environment(AppServices.self) private var services

  @State private var username = ""
  @State private var password = ""
  @State private var region = TandemRegion.us
  @State private var alert: CredentialAlert?
  @State private var isShowingPassword = false
  @State private var isValidating = false

  var body: some View {
    PumpSyncScreen {
      GlassSection("Tandem Source") {
        TextField("Username", text: $username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .frame(minHeight: 44)
          .accessibilityLabel("Tandem username")
          .accessibilityHint("Enter the username for your pump account")

        GlassDivider(leadingPadding: 0)

        if isShowingPassword {
          TextField("Password", text: $password)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: 44)
            .accessibilityLabel("Tandem password")
            .accessibilityHint("Enter the password for your pump account")
        } else {
          SecureField("Password", text: $password)
            .textContentType(.password)
            .frame(minHeight: 44)
            .accessibilityLabel("Tandem password")
            .accessibilityHint("Enter the password for your pump account")
        }

        GlassDivider(leadingPadding: 0)

        Toggle("Show password", isOn: $isShowingPassword)
          .frame(minHeight: 44)
          .accessibilityHint("Shows or hides the Tandem password text")

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
          .accessibilityLabel("Tandem region")
          .accessibilityValue(region.title)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
      }

      Button {
        Task {
          await validateAndSave()
        }
      } label: {
        GlassPrimaryLabel(title: primaryActionTitle, systemImage: primaryActionSystemImage)
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canUsePrimaryAction)
      .accessibilityHint(primaryActionHint)

      Button(role: .destructive) {
        delete()
      } label: {
        GlassPrimaryLabel(title: "Remove Credentials", systemImage: "trash")
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!services.credentialStore.hasStoredCredentials)
      .accessibilityHint("Removes the saved pump account credentials from this device")
    }
    .navigationTitle("Tandem")
    .onAppear(perform: load)
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

  private var canUsePrimaryAction: Bool {
    hasRequiredFields && !isValidating && !services.authService.isConnecting
  }

  private var primaryActionTitle: String {
    if isValidating {
      return "Saving"
    }

    if services.authService.isConnecting {
      return "Connecting"
    }

    return "Save Credentials"
  }

  private var primaryActionSystemImage: String {
    "key.fill"
  }

  private var primaryActionHint: String {
    "Validates the pump account credentials using the current PumpSync connection, then saves them on this device"
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
      services.diagnosticsLogStore.record(source: .credential, severity: .error, title: "Credentials unavailable", message: error.localizedDescription)
    }
  }

  private func validateAndSave() async {
    isValidating = true
    defer { isValidating = false }

    guard let accessToken = await accessTokenForValidation() else {
      return
    }

    do {
      let credentials = currentCredentials
      let response = try await services.apiClient.validateTandemCredentials(
        TandemCredentialValidationRequest(tandem: credentials),
        accessToken: accessToken
      )

      guard response.validated else {
        alert = CredentialAlert(
          title: "Save Failed",
          message: "Account details could not be validated. Check them and try again."
        )
        services.diagnosticsLogStore.record(source: .credential, severity: .warning, title: "Credentials validation rejected")
        return
      }

      try services.credentialStore.saveValidated(credentials)
      alert = CredentialAlert(
        title: "Credentials Saved",
        message: "Credentials validated and saved to this device."
      )
      services.diagnosticsLogStore.record(source: .credential, title: "Credentials saved")
    } catch {
      if (error as? APIClientError)?.isAuthenticationFailure == true {
        services.authService.clearSessionForAuthenticationFailure()
      }
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials save failed")
      alert = CredentialAlert(
        title: "Save Failed",
        message: "Credentials could not be validated or saved. Check them and try again."
      )
    }
  }

  private func accessTokenForValidation() async -> String? {
    if let accessToken = await services.authService.accessTokenRecoveringIfNeeded() {
      return accessToken
    }

    alert = CredentialAlert(
      title: "Connection Needed",
      message: services.authService.connectionRequiredMessage
    )
    return nil
  }

  private func delete() {
    do {
      try services.credentialStore.delete()
      username = ""
      password = ""
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
}

private struct CredentialAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
