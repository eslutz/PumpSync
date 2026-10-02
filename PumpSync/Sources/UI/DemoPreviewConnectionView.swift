import SwiftUI

struct DemoPreviewConnectionView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: DemoPreviewSession?
    @State private var username = ""
    @State private var password = ""
    @State private var region = TandemRegion.us
    @State private var range = InitialImportRange.pastTwoDays
    @State private var concentration = InsulinConcentration.u100
    @State private var message: String?
    @State private var busy = false
    @State private var generation = UUID()
    @State private var work: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sample data — nothing is saved to Apple Health").font(.headline)
                    Text("This separate sample connection leaves your regular connection and import history intact.")
                }
                Section("Sample Account") {
                    TextField("Sample username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Sample password", text: $password).textContentType(.password)
                    Picker("Region", selection: $region) { ForEach(TandemRegion.allCases) { Text($0.title).tag($0) } }
                    Picker("History range", selection: $range) { ForEach(InitialImportRange.allCases) { Text($0.title).tag($0) } }
                    Picker("Insulin concentration", selection: $concentration) { ForEach(InsulinConcentration.allCases) { Text($0.title).tag($0) } }
                    Button("Connect and Preview") { start() }.disabled(busy || username.isEmpty || password.isEmpty)
                    if busy { ProgressView("Connecting to sample service…") }
                    if let message { Text(message).foregroundStyle(.secondary) }
                }
                if let session, session.credentials != nil {
                    Section {
                        NavigationLink("View Sample Preview") {
                            ImportPreviewView(controller: session.controller, isSample: true, retry: { await load(session) })
                                .task { await load(session) }
                        }
                    }
                }
            }
            .navigationTitle("Sample Preview")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { close(); dismiss() } } }
        }
        .onChange(of: username) { _, _ in invalidateInputs() }
        .onChange(of: password) { _, _ in invalidateInputs() }
        .onChange(of: region) { _, _ in invalidateInputs() }
        .onDisappear { close() }
        .onChange(of: scenePhase) { _, phase in
            // `.inactive` is a transient state during system interruptions and
            // presentation transitions. Keep the preview sheet alive there;
            // clear its isolated session when the app actually backgrounds.
            if phase == .background {
                close()
                dismiss()
            }
        }
    }

    private func start() {
        guard services.demoPreviewActive else { return }
        busy = true
        message = nil
        let id = generation
        let credentials = TandemCredentials(username: username, password: password, region: region.rawValue)
        work = Task { @MainActor in
            do {
                let preview = try DemoPreviewSession.make(diagnostics: services.diagnosticsLogStore)
                session?.close()
                session = preview
                await preview.connect()
                guard id == generation, !Task.isCancelled else { preview.close(); return }
                guard preview.authService.isSignedIn else {
                    message = preview.authService.errorMessage ?? "The sample connection could not be established."
                    busy = false
                    return
                }
                try await preview.validate(credentials: credentials)
                guard id == generation, !Task.isCancelled else { preview.close(); return }
                busy = false
            } catch {
                guard id == generation, !Task.isCancelled else { return }
                message = "The sample connection could not be validated. Check the details and try again."
                busy = false
            }
        }
    }

    private func load(_ session: DemoPreviewSession) async {
        guard let credentials = session.credentials,
              let context = session.authService.operationImportSnapshot(credentialRevision: session.credentialRevision) else { return }
        let now = Date()
        await session.controller.load(request: .init(tandem: credentials, minDate: range.minimumDate(relativeTo: now), maxDate: now, timeZoneIdentifier: TimeZone.current.identifier), context: context, concentration: concentration)
    }

    private func invalidateInputs() {
        generation = UUID()
        work?.cancel()
        work = nil
        session?.invalidateCredentials()
        busy = false
    }

    private func close() {
        generation = UUID()
        work?.cancel()
        work = nil
        session?.close()
        session = nil
        username = ""
        password = ""
        busy = false
        services.endDemoPreview()
    }
}
