import Foundation

@MainActor
final class RealImportPreviewSession {
    let controller: ImportPreviewController
    private let context: () -> ImportSessionSnapshot?
    private let credentialStore: TandemCredentialStore
    private let metadataStore: SyncMetadataStore
    private let concentrationStore: InsulinConcentrationStore

    init(dataSource: any TandemDataSource, credentialStore: TandemCredentialStore, metadataStore: SyncMetadataStore, concentrationStore: InsulinConcentrationStore, diagnostics: DiagnosticsLogStore? = nil, previewSource: DataSourceMode = .tandemSource) {
        self.credentialStore = credentialStore
        self.metadataStore = metadataStore
        self.concentrationStore = concentrationStore
        let snapshot = { () -> ImportSessionSnapshot? in
            guard var context = credentialStore.currentImportSnapshot else { return nil }
            context.dataSourceMode = previewSource
            return context
        }
        context = snapshot
        controller = ImportPreviewController(dataSource: dataSource, diagnostics: diagnostics, currentContext: snapshot)
    }

    var currentContext: ImportSessionSnapshot? { context() }

    func loadIfNeeded() async {
        controller.validateSnapshot()
        if case .idle = controller.state { await load() }
    }

    func load() async {
        guard let credentials = try? credentialStore.load(), credentialStore.hasValidatedCredentials,
              let context = currentContext else {
            controller.fail("Validate your Tandem account in Settings to inspect records.")
            return
        }
        let now = Date()
        // Preview may use a cursor only when its durable owner matches. It does
        // not mutate live sync metadata while inspecting replacement credentials.
        let owner = credentialStore.accountId.map { TandemSyncOwner(accountId: $0) }
        let watermark = owner != nil && metadataStore.metadata.owner == owner ? metadataStore.metadata.syncWatermark : nil
        let minimum = watermark ?? metadataStore.metadata.initialImportRange.minimumDate(relativeTo: now)
        await controller.load(request: .init(tandem: credentials, minDate: minimum, maxDate: now, timeZoneIdentifier: TimeZone.current.identifier), context: context, concentration: concentrationStore.concentration)
    }
}
