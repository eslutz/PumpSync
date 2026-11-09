import SwiftUI

struct TandemCredentialForm: View {
  @Environment(AppServices.self) private var services
  @Environment(\.editingScreenDepartureID) private var editingScreenDepartureID
  @Environment(\.scenePhase) private var scenePhase
  @State private var validation = CredentialValidationLifetime()

  @State private var username = ""
  @State private var password = ""
  @State private var region = TandemRegion.us
  @State private var alert: CredentialAlert?
  @State private var isShowingPassword = false
  private var isValidating: Bool { validation.isRunning }
  @State private var lastValidatedCredentials: TandemCredentials?
  @State private var baselineUsername = ""
  @State private var baselineRegion = TandemRegion.us
  @State private var isConfirmingRemoval = false
  @State private var isEditing = false
  @FocusState private var focusedField: CredentialField?

  private enum CredentialField { case username, password }

  var body: some View {
    Form {
      if services.credentialStore.hasStoredCredentials && !isEditing {
        SavedTandemAccountSections(
          username: baselineUsername, region: baselineRegion,
          canEdit: !services.syncCoordinator.hasActiveSyncExecution && !services.authService.isReplacingConnection,
          canRemove: !services.syncCoordinator.hasActiveSyncExecution,
          edit: { isEditing = true }, remove: { isConfirmingRemoval = true }
        )
      } else {
        Section {
          TextField("Username", text: $username)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel("Tandem username")
            .accessibilityHint("Enter the username for your pump account")
            .focused($focusedField, equals: .username)
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

          HStack {
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
            .accessibilityLabel("Tandem password")
            .accessibilityHint("Enter the password for your pump account")
            .focused($focusedField, equals: .password)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }

            Button(isShowingPassword ? "Hide password" : "Show password",
              systemImage: isShowingPassword ? "eye.slash" : "eye") {
              isShowingPassword.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(password.isEmpty)
          }

          Picker("Tandem region", selection: $region) {
            ForEach(TandemRegion.allCases) { choice in Text(choice.title).tag(choice) }
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("TandemRegionPicker")

          Button {
            focusedField = nil
            validation.start { await validateAndSave() }
          } label: {
            if isValidating {
              HStack {
                ProgressView()
                Text(primaryActionTitle)
                  .fixedSize(horizontal: false, vertical: true)
              }
            } else {
              Label {
                Text(primaryActionTitle)
                  .fixedSize(horizontal: false, vertical: true)
              } icon: {
                Image(systemName: "key.fill")
              }
            }
          }
          .disabled(!canUsePrimaryAction)
          .accessibilityHint(primaryActionHint)
        } header: {
          Text("Tandem Source")
            .foregroundStyle(Color.primary)
        } footer: {
          Text("Enter the password you currently use for Tandem. This updates the login saved in PumpSync; it does not change your Tandem password.")
            .font(.body)
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .headerProminence(.increased)
        .disabled(isValidating)
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .privacySensitive()
    .redacted(reason: scenePhase == .active ? [] : .privacy)
    .navigationTitle("Tandem")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: load)
    .onDisappear(perform: discardDraft)
    .onChange(of: editingScreenDepartureID) { _, _ in discardDraft() }
    .onChange(of: services.backendConfigurationStore.revision) { _, _ in
      validation.cancel()
      password = ""
      isShowingPassword = false
      lastValidatedCredentials = nil
    }
    .onChange(of: scenePhase) { _, newPhase in
      // A revealed password must not survive backgrounding: the plain
      // TextField (unlike SecureField) would otherwise be captured in the
      // app-switcher snapshot and remain visible on return.
      if newPhase != .active {
        isShowingPassword = false
        password = ""
        lastValidatedCredentials = nil
        validation.cancel()
      }
    }
    .confirmationDialog("Remove saved credentials?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
      Button("Remove Credentials", role: .destructive, action: delete)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Removes the Tandem sign-in from this device and stops pump sync until you save an account again. Current-account sync history resets. Existing Apple Health samples, duplicate-prevention records, backend metadata, and your subscription remain.")
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

  enum ActionState: Equatable {
    case save
    case saveDisabled
  }

  static func actionState(username: String, password: String) -> ActionState {
    username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty ? .saveDisabled : .save
  }

  private var canUsePrimaryAction: Bool {
    Self.actionState(username: username, password: password) == .save
      && !isValidating
      && !services.authService.isConnecting
      && !services.authService.isReplacingConnection
      && !services.syncCoordinator.hasActiveSyncExecution
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

  private var primaryActionHint: String {
    "Validates your current Tandem login, then saves it on this device"
  }

  static func shouldSkipRevalidation(current: TandemCredentials, lastValidated: TandemCredentials?) -> Bool {
    guard let lastValidated else {
      return false
    }

    return current == lastValidated
  }

  private func discardDraft() {
    validation.cancel()
    focusedField = nil
    password = ""
    isShowingPassword = false
    lastValidatedCredentials = nil
    load()
    isEditing = false
    alert = nil
    isConfirmingRemoval = false
  }

  private func load() {
    username = ""
    region = .us
    baselineUsername = ""
    baselineRegion = .us
    do {
      guard let credentials = try services.credentialStore.load() else {
        return
      }

      // The password is intentionally not loaded into view state: doing so
      // put the plaintext password one tap ("Show password") away from
      // anyone with momentary access to an unlocked device. The entered
      // password validates the current Tandem login, not the saved password.
      username = credentials.username
      region = TandemRegion(rawValue: credentials.region) ?? .us
      baselineUsername = credentials.username
      baselineRegion = region
    } catch {
      services.diagnosticsLogStore.record(source: .credential, severity: .error, title: "Credentials unavailable", message: error.localizedDescription)
    }
  }

  private func validateAndSave() async {
    guard !Task.isCancelled else { return }
    let credentials = currentCredentials
    let configurationRevision = services.backendConfigurationStore.revision

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

    guard let accessToken = await accessTokenForValidation(configurationRevision: configurationRevision),
          !Task.isCancelled,
          configurationRevision == services.backendConfigurationStore.revision,
          let submittedConnection = services.authService.authenticatedConnection,
          submittedConnection.session.accessToken == accessToken else {
      return
    }

    do {
      let response = try await services.apiClient.validateTandemCredentials(
        TandemCredentialValidationRequest(tandem: credentials, timeZoneIdentifier: TimeZone.current.identifier),
        accessToken: accessToken
      )

      try Task.checkCancellation()
      guard configurationRevision == services.backendConfigurationStore.revision else { return }
      guard response.validated else {
        alert = CredentialAlert(
          title: "Save Failed",
          message: "Account details could not be validated. Check them and try again."
        )
        services.diagnosticsLogStore.record(source: .credential, severity: .warning, title: "Credentials validation rejected")
        return
      }

      try services.credentialStore.saveValidated(credentials)
      lastValidatedCredentials = nil
      isEditing = false
      baselineUsername = credentials.username
      baselineRegion = TandemRegion(rawValue: credentials.region) ?? .us
      password = ""
      isShowingPassword = false
      alert = CredentialAlert(
        title: "Credentials Saved",
        message: "Credentials validated and saved to this device."
      )
      services.diagnosticsLogStore.record(source: .credential, title: "Credentials saved")
    } catch {
      guard !Task.isCancelled, configurationRevision == services.backendConfigurationStore.revision else { return }
      if (error as? APIClientError)?.isAuthenticationFailure == true {
        services.authService.clearSessionForAuthenticationFailure(expectedSource: submittedConnection)
      }
      services.diagnosticsLogStore.record(error: error, source: .credential, title: "Credentials save failed")
      alert = CredentialAlert(
        title: "Save Failed",
        message: "Credentials could not be validated or saved. Check them and try again."
      )
    }
  }

  private func accessTokenForValidation(configurationRevision: Int) async -> String? {
    if let accessToken = await services.authService.accessTokenRecoveringIfNeeded() {
      return accessToken
    }

    guard !Task.isCancelled, configurationRevision == services.backendConfigurationStore.revision else { return nil }
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

private struct SavedTandemAccountSections: View {
  let username: String
  let region: TandemRegion
  let canEdit: Bool
  let canRemove: Bool
  let edit: () -> Void
  let remove: () -> Void

  var body: some View {
    Section {
      LabeledContent {
        Text(username)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      } label: {
        Text("Username")
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.body)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Tandem username")
      .accessibilityValue(username)
      LabeledContent {
        Text(region.title)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      } label: {
        Text("Region")
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.body)
      LabeledContent {
        Text("Saved on this device")
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      } label: {
        Text("Password")
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.body)
      Button(action: edit) {
        Label {
          Text("Change Account Details")
            .font(.body)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "pencil")
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .disabled(!canEdit)
    } header: {
      Text("Saved Account")
        .foregroundStyle(Color.primary)
    }
    .headerProminence(.increased)
    Section {
      Button(role: .destructive, action: remove) {
        Label {
          Text("Remove Credentials")
            .font(.body)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "trash")
        }
        .foregroundStyle(Color.primary)
      }
      .disabled(!canRemove)
    }
  }
}

private struct CredentialAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}

#if DEBUG
#Preview("Saved Tandem account") {
  NavigationStack {
    Form {
      SavedTandemAccountSections(username: "demo@example.com", region: .us,
        canEdit: true, canRemove: true, edit: {}, remove: {})
    }
    .navigationTitle("Tandem")
  }
}
#endif
