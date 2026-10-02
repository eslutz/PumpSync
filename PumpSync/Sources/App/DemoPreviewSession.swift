import Foundation
import Observation

@MainActor
@Observable
final class DemoPreviewSession {
    static let defaultBaseURL = URL(string: "https://demo.pumpsync.ericslutz.dev/api")!
    let apiClient: PumpSyncAPIClient
    let authService: AuthService
    @ObservationIgnored lazy var controller = ImportPreviewController(apiClient: apiClient, authService: authService, purpose: .sample, diagnostics: diagnostics, currentContext: { [weak self] in
        guard let self else { return nil }
        return authService.operationImportSnapshot(credentialRevision: credentialRevision)
    })
    private(set) var credentials: TandemCredentials?
    private(set) var credentialRevision = 0
    private let diagnostics: DiagnosticsLogStore?
    private var generation = UUID()

    init(apiClient: PumpSyncAPIClient, authService: AuthService, diagnostics: DiagnosticsLogStore?) {
        self.diagnostics = diagnostics
        self.apiClient = apiClient
        self.authService = authService
    }

    static func make(baseURL: URL = defaultBaseURL, diagnostics: DiagnosticsLogStore? = nil) throws -> DemoPreviewSession {
        let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync.demo-preview")
        let account = "preview-installation-identity"
        let installationId: String
        if let data = try keychain.readData(account: account), let stored = String(data: data, encoding: .utf8) {
            installationId = stored
        } else {
            installationId = UUID().uuidString
            try keychain.writeData(Data(installationId.utf8), account: account)
        }
        let api = PumpSyncAPIClient(baseURL: baseURL, urlSession: .shared)
        let configuration = BackendConfigurationStore.ephemeral(selfHostedBaseURL: baseURL, installationId: installationId)
        let auth = AuthService(apiClient: api, configurationStore: configuration, sessionStore: nil, purpose: .preview, proofProvider: DeviceSessionProofProvider(keychain: keychain))
        return DemoPreviewSession(apiClient: api, authService: auth, diagnostics: diagnostics)
    }

    func connect() async {
        let id = generation
        await authService.connectSelfHosted()
        if id != generation || Task.isCancelled || authService.session?.isSyntheticDemo != true { authService.clearSessionForConnectionChange() }
    }

    func validate(credentials: TandemCredentials) async throws {
        invalidateCredentials()
        let id = generation
        guard let token = await authService.accessTokenRecoveringIfNeeded() else { throw PreviewError.connectionRequired }
        let response = try await apiClient.validateTandemCredentials(.init(tandem: credentials, timeZoneIdentifier: TimeZone.current.identifier), accessToken: token)
        guard id == generation, !Task.isCancelled else { throw CancellationError() }
        guard response.validated else { throw PreviewError.invalidCredentials }
        self.credentials = credentials
        credentialRevision &+= 1
    }

    func invalidateCredentials() {
        generation = UUID()
        controller.cancel()
        credentials = nil
        credentialRevision &+= 1
    }

    func close() {
        generation = UUID()
        controller.cancel()
        credentials = nil
        credentialRevision &+= 1
        authService.clearSessionForConnectionChange()
    }
}
