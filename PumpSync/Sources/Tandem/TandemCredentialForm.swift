import SwiftUI

struct TandemCredentialForm: View {
  @Environment(AppServices.self) private var services
  @Environment(\.scenePhase) private var scenePhase

  @State private var username = ""
  @State private var password = ""
  @State private var region = TandemRegion.us
  @State private var alert: CredentialAlert?
  @State private var isShowingPassword = false
  @State private var isValidating = false
  @State private var lastValidatedCredentials: TandemCredentials?
  @State private var baselineUsername = ""
  @State private var baselineRegion = TandemRegion.us
  @State private var isConfirmingRemoval = false

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

        HStack(spacing: 12) {
          Group {
            if isShowingPassword {
              TextField("Password", text: $password)
            } else {
              SecureField("Password", text: $password)
            }
          }
          .textContentType(.password)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .frame(minHeight: 44)
          .accessibilityLabel("Tandem password")
          .accessibilityHint("Enter the password for your pump account")

          Button {
            isShowingPassword.toggle()
          } label: {
            Image(systemName: isShowingPassword ? "eye.slash" : "eye")
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .disabled(password.isEmpty)
          .accessibilityLabel(isShowingPassword ? "Hide password" : "Show password")
        }

        if services.credentialStore.hasStoredCredentials {
          Text("A password is already saved on this device. Enter it again to change your username, password, or region.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }

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
      // privacySensitive alone is inert — SwiftUI only redacts it while a
      // .privacy redaction reason is active, which nothing applies by
      // default. Drive it from the scene phase so the app-switcher snapshot
      // (taken after the scene resigns active) never captures a revealed
      // password.
      .privacySensitive()
      .redacted(reason: scenePhase == .active ? [] : .privacy)

      Button(role: actionState == .remove ? .destructive : nil) {
        if actionState == .remove {
          isConfirmingRemoval = true
        } else {
          Task {
            await validateAndSave()
          }
        }
      } label: {
        GlassPrimaryLabel(title: primaryActionTitle, systemImage: primaryActionSystemImage)
      }
      .buttonStyle(GroupedActionButtonStyle())
      .disabled(!canUsePrimaryAction)
      .accessibilityHint(primaryActionHint)

      if actionState == .saveDisabled && services.credentialStore.hasStoredCredentials && (usernameChanged || regionChanged) && password.isEmpty {
        Text("Enter your password to save changes.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 4)
      }
    }
    .navigationTitle("Tandem")
    .onAppear(perform: load)
    .onChange(of: scenePhase) { _, newPhase in
      // A revealed password must not survive backgrounding: the plain
      // TextField (unlike SecureField) would otherwise be captured in the
      // app-switcher snapshot and remain visible on return.
      if newPhase != .active {
        isShowingPassword = false
      }
    }
    .confirmationDialog("Remove saved credentials?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
      Button("Remove Credentials", role: .destructive, action: delete)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You will need to enter your Tandem account details before syncing again.")
    }
    .alert(
      alert?.title ?? "",
      isPresented: Binding(
        get: { alert != nil },
        set: { isPresented in
          if !isPresented {
            alert = nil
          }
        }
      ),
      presenting: alert
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { alert in
      Text(alert.message)
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

  enum ActionState: Equatable {
    case save
    case saveDisabled
    case remove
  }

  static func actionState(
    hasStoredCredentials: Bool,
    usernameChanged: Bool,
    regionChanged: Bool,
    password: String
  ) -> ActionState {
    if !hasStoredCredentials {
      return password.isEmpty ? .saveDisabled : .save
    }
    if password.isEmpty {
      return usernameChanged || regionChanged ? .saveDisabled : .remove
    }
    return .save
  }

  private var usernameChanged: Bool {
    username.trimmingCharacters(in: .whitespacesAndNewlines) != baselineUsername
  }

  private var regionChanged: Bool { region != baselineRegion }

  private var actionState: ActionState {
    Self.actionState(
      hasStoredCredentials: services.credentialStore.hasStoredCredentials,
      usernameChanged: usernameChanged,
      regionChanged: regionChanged,
      password: password
    )
  }

  private var canUsePrimaryAction: Bool {
    actionState != .saveDisabled
      && (actionState == .remove || hasRequiredFields)
      && !isValidating
      && !services.authService.isConnecting
  }

  private var primaryActionTitle: String {
    if isValidating {
      return "Saving"
    }

    if services.authService.isConnecting {
      return "Connecting"
    }

    return actionState == .remove ? "Remove Credentials" : "Save Credentials"
  }

  private var primaryActionSystemImage: String {
    actionState == .remove ? "trash" : "key.fill"
  }

  private var primaryActionHint: String {
    actionState == .remove
      ? "Removes the saved pump account credentials from this device"
      : "Validates the pump account credentials using the current PumpSync connection, then saves them on this device"
  }

  static func shouldSkipRevalidation(current: TandemCredentials, lastValidated: TandemCredentials?) -> Bool {
    guard let lastValidated else {
      return false
    }

    return current == lastValidated
  }

  private func load() {
    do {
      guard let credentials = try services.credentialStore.load() else {
        return
      }

      // The password is intentionally not loaded into view state: doing so
      // put the plaintext password one tap ("Show password") away from
      // anyone with momentary access to an unlocked device. Changing any
      // field, including just the username or region, requires re-entering
      // the password.
      username = credentials.username
      region = TandemRegion(rawValue: credentials.region) ?? .us
      baselineUsername = credentials.username
      baselineRegion = region
    } catch {
      services.diagnosticsLogStore.record(source: .credential, severity: .error, title: "Credentials unavailable", message: error.localizedDescription)
    }
  }

  private func validateAndSave() async {
    let credentials = currentCredentials

    // Region determines a different Tandem login endpoint (see the backend's
    // TandemSourceOptions Us/Eu configs), so a region change always needs a
    // fresh validation call, and the stored password is intentionally never
    // loaded into view state (see load()), so there's no way to detect an
    // unchanged password against the persisted baseline without holding
    // that plaintext again. The one case that's safe to skip without either
    // of those: an exact repeat of the form state that was just
    // successfully validated and saved in this same screen session, e.g.
    // tapping Save again after dismissing the confirmation.
    guard !Self.shouldSkipRevalidation(current: credentials, lastValidated: lastValidatedCredentials) else {
      alert = CredentialAlert(
        title: "Credentials Saved",
        message: "Credentials validated and saved to this device."
      )
      services.diagnosticsLogStore.record(source: .credential, title: "Credentials save skipped", message: "Form matches the last successfully validated save; no Tandem revalidation was needed.")
      return
    }

    isValidating = true
    defer { isValidating = false }

    guard let accessToken = await accessTokenForValidation() else {
      return
    }

    do {
      let response = try await services.apiClient.validateTandemCredentials(
        TandemCredentialValidationRequest(tandem: credentials, timeZoneIdentifier: TimeZone.current.identifier),
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
      lastValidatedCredentials = credentials
      baselineUsername = credentials.username
      baselineRegion = region
      password = ""
      isShowingPassword = false
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
      baselineUsername = ""
      baselineRegion = .us
      region = .us
      lastValidatedCredentials = nil
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
