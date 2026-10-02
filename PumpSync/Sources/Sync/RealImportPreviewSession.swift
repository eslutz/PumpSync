import Foundation

@MainActor
final class RealImportPreviewSession {
    let controller: ImportPreviewController
    private let authService: AuthService
    private let credentialStore: TandemCredentialStore
    private let metadataStore: SyncMetadataStore
    private let concentrationStore: InsulinConcentrationStore

    init(apiClient: PumpSyncAPIClient, authService: AuthService, credentialStore: TandemCredentialStore, metadataStore: SyncMetadataStore, concentrationStore: InsulinConcentrationStore, diagnostics: DiagnosticsLogStore? = nil) {
        self.authService = authService
        self.credentialStore = credentialStore
        self.metadataStore = metadataStore
        self.concentrationStore = concentrationStore
        controller = ImportPreviewController(apiClient: apiClient, authService: authService, diagnostics: diagnostics, currentContext: {
            guard credentialStore.hasValidatedCredentials else { return nil }
            return authService.operationImportSnapshot(credentialRevision: credentialStore.revision)
        })
    }

    func load() async {
        guard let credentials = try? credentialStore.load(), credentialStore.hasValidatedCredentials,
              let context = authService.operationImportSnapshot(credentialRevision: credentialStore.revision) else {
            controller.fail("Your connection or pump credentials changed. Reconnect and validate your pump account in Settings.")
            return
        }
        let now = Date()
        let minimum = metadataStore.metadata.syncWatermark ?? metadataStore.metadata.initialImportRange.minimumDate(relativeTo: now)
        await controller.load(request: .init(tandem: credentials, minDate: minimum, maxDate: now, timeZoneIdentifier: TimeZone.current.identifier), context: context, concentration: concentrationStore.concentration)
    }
}
