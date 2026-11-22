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
  @State private var baselineUsername = ""
  @State private var baselineRegion = TandemRegion.us
  @State private var isConfirmingRemoval = false
  @State private var isEditing = false
  @FocusState private var focusedField: CredentialField?

  private enum CredentialField { case username, password }

  var body: some View {
    Form {
      if services.credentialStore.hasStoredCredentials && !isEditing {
        if services.credentialStore.needsDirectReconnect {
          Section {
            Button {
              validation.start { await reconnectSavedAccount() }
            } label: {
              if isValidating { ProgressView("Connecting to Tandem…") }
              else { Label("Reconnect to Tandem", systemImage: "key.fill") }
            }
            .disabled(isValidating || services.syncCoordinator.hasActiveSyncExecution)
          } footer: {
            Text("Use the sign-in saved on this device to connect directly to Tandem.")
          }
        }
        SavedTandemAccountSections(
          username: baselineUsername, region: baselineRegion,
          canEdit: !isValidating && !services.syncCoordinator.hasActiveSyncExecution,
          canRemove: !isValidating && !services.syncCoordinator.hasActiveSyncExecution,
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
            validation.start { await validateAndSave(currentCredentials) }
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
          Text("Enter the password you currently use for Tandem. PumpSync validates the sign-in directly with Tandem and saves it on this device.")
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
    .onChange(of: scenePhase) { _, newPhase in
      // A revealed password must not survive backgrounding: the plain
      // TextField (unlike SecureField) would otherwise be captured in the
      // app-switcher snapshot and remain visible on return.
      if newPhase != .active {
        isShowingPassword = false
        password = ""
        validation.cancel()
      }
    }
    .confirmationDialog("Remove saved credentials?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
      Button("Remove Credentials", role: .destructive, action: delete)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Removes the Tandem sign-in from this device and stops pump sync until you save an account again. The next account will start with a new sync history. You can manage previous imports in Apple Health.")
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
      && !services.syncCoordinator.hasActiveSyncExecution
  }

  private var primaryActionTitle: String {
    if isValidating {
      return "Saving"
    }

    return "Save Credentials"
  }

  private var primaryActionHint: String {
    "Validates your current Tandem login, then saves it on this device"
  }

  private func discardDraft() {
    validation.cancel()
    focusedField = nil
    password = ""
    isShowingPassword = false
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

  private func reconnectSavedAccount() async {
    do {
      guard services.credentialStore.needsDirectReconnect,
            let credentials = try services.credentialStore.load() else { return }
      await validateAndSave(credentials)
    } catch {
      alert = CredentialAlert(title: "Account Unavailable", message: "Unlock your device and try again.")
    }
  }

  private func validateAndSave(_ credentials: TandemCredentials) async {
    guard !Task.isCancelled else { return }
    let revision = services.credentialStore.revision
    do {
      try await services.dataSource.validate(credentials, timeZone: .current)
      try Task.checkCancellation()
      guard revision == services.credentialStore.revision else { return }
      try services.credentialStore.saveValidated(credentials)
      isEditing = false
      baselineUsername = credentials.username
      baselineRegion = TandemRegion(rawValue: credentials.region) ?? .us
      password = ""
      isShowingPassword = false
      alert = CredentialAlert(title: "Account Connected", message: "Your Tandem sign-in is saved on this device.")
      services.diagnosticsLogStore.record(source: .credential, title: "Tandem account validated")
    } catch {
      guard !Task.isCancelled, revision == services.credentialStore.revision else { return }
      let message = (error as? DirectTandemError)?.localizedDescription ?? "The sign-in could not be saved on this device. Try again."
      services.diagnosticsLogStore.record(source: .credential, severity: .warning, title: "Tandem account setup failed")
      alert = CredentialAlert(title: "Account Setup Failed", message: message)
    }
  }

  private func delete() {
    do {
      try services.credentialStore.delete()
      username = ""
      password = ""
      baselineUsername = ""
      baselineRegion = .us
      region = .us
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
      EditAccountButton(isEnabled: canEdit, edit: edit)
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

/// Lets the native control expose the same Dynamic Type font used to draw its title.
private struct EditAccountButton: UIViewRepresentable {
  let isEnabled: Bool
  let edit: () -> Void

  func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .system)
    button.contentHorizontalAlignment = .leading
    button.setTitle("Change Account Details", for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .body)
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    button.titleLabel?.numberOfLines = 0
    button.titleLabel?.lineBreakMode = .byWordWrapping
    return button
  }

  func updateUIView(_ button: UIButton, context: Context) {
    button.isEnabled = isEnabled
    // A constant identifier replaces the previous action when SwiftUI updates the view.
    button.addAction(UIAction(identifier: .init("editAccount")) { _ in edit() }, for: .touchUpInside)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView button: UIButton, context: Context) -> CGSize? {
    guard let width = proposal.width, let title = button.titleLabel else { return nil }
    let titleSize = title.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude))
    return .init(width: width, height: max(44, ceil(titleSize.height)))
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
