import Foundation
import Observation

@MainActor
@Observable
final class ImportPreviewController {
    enum State {
        case idle, loading, ready(ImportPlan), failed(String)
    }
    private(set) var state: State = .idle {
        didSet {
            let summary: String
            switch state {
            case .idle: summary = "state=idle"
            case .loading: summary = "state=loading"
            case .ready(let plan): summary = "state=ready source=\(plan.context.dataSourceMode.rawValue) count=\(plan.downloadedRecordCount)"
            case .failed: summary = "state=failed reason=previewUnavailable"
            }
            diagnostics?.record(source: .sync, title: "Import preview", message: "purpose=real \(summary)")
        }
    }
    private let diagnostics: DiagnosticsLogStore?
    private let apiClient: PumpSyncAPIClient
    private let authService: AuthService
    private var operationID = UUID()
    private var task: Task<Void, Never>?
    private let currentContext: () -> ImportSessionSnapshot?
    private(set) var loadedAt: Date?
    private(set) var isRefreshing = false
    private(set) var refreshError: String?

    var recordsNewestFirst: [PlannedImportSample] {
        guard case .ready(let plan) = state else { return [] }
        // ImportPlanner keeps a deterministic ascending order for import work.
        return Array(plan.samples.reversed())
    }

    init(apiClient: PumpSyncAPIClient, authService: AuthService, diagnostics: DiagnosticsLogStore? = nil, currentContext: @escaping () -> ImportSessionSnapshot?) {
        self.diagnostics = diagnostics
        self.apiClient = apiClient
        self.authService = authService
        self.currentContext = currentContext
    }

    func load(request: TandemSyncRequest, context: ImportSessionSnapshot, concentration: InsulinConcentration) async {
        validateSnapshot()
        suspend()
        if case .ready(let plan) = state, Self.sameInspectionOwner(plan.context, context) {
            isRefreshing = true
        } else {
            cancel()
            state = .loading
        }
        refreshError = nil
        let id = operationID
        let configuration = authService.importConfigurationSnapshot
        let task = Task { @MainActor in
            var context = context
            var submittedConnection: AuthenticatedConnection?
            do {
                let capabilities = try await apiClient.capabilities()
                guard capabilities.supportsImportPreview else { throw PreviewError.upgradeRequired }
                guard capabilities.dataSourceMode == context.dataSourceMode else { throw HealthImportError.sourceMismatch }
                guard id == operationID, !Task.isCancelled else { return }
                guard context == currentContext() else { fail("Your connection or pump account changed. Reconnect or validate the account, then load records again."); return }
                let recovery = await authService.recoverSessionIfNeeded()
                guard !Task.isCancelled, id == operationID else { return }
                guard case .ready(let recovered, let transition) = recovery else { throw PreviewError.connectionRequired }
                let token = recovered.session.accessToken
                // Recovery may replace continuity before any preview records
                // have been downloaded. Capture that fresh source once, only
                // while the original configuration/account still owns the view.
                if transition == .reenrolled, let fresh = currentContext(),
                   configuration == authService.importConfigurationSnapshot,
                   fresh.backendIdentity == context.backendIdentity,
                   fresh.configurationRevision == context.configurationRevision,
                   fresh.credentialRevision == context.credentialRevision,
                   fresh.dataSourceMode == context.dataSourceMode {
                    context = fresh
                }
                guard context == currentContext() else { fail("Your connection or pump account changed. Reconnect or validate the account, then load records again."); return }
                guard let connection = authService.authenticatedConnection, connection.session.accessToken == token else { throw PreviewError.connectionRequired }
                submittedConnection = connection
                let response = try await apiClient.previewTandem(request, accessToken: token)
                guard !Task.isCancelled, id == operationID else { return }
                guard context == currentContext(), context.backendIdentity == ImportSessionSnapshot.canonicalBackendIdentity(apiClient.baseURL) else { fail("Your connection or pump account changed. Reconnect or validate the account, then load records again."); return }
                let plan = try ImportPlanner.makePlan(response: response, context: context, concentration: concentration)
                loadedAt = Date()
                state = .ready(plan)
            } catch {
                guard !Task.isCancelled, id == operationID else { return }
                // Backend messages can contain provider identifiers. Keep preview errors local.
                if let error = error as? APIClientError, error.isAuthenticationFailure {
                    if let submittedConnection { authService.clearSessionForAuthenticationFailure(expectedSource: submittedConnection) }
                    fail("The connection expired. Reconnect to the service and try again.")
                }
                else if error is HealthImportError { fail("The service returned unverified or invalid records. Reconnect or update the backend before inspecting records.") }
                else {
                    let message = (error as? PreviewError)?.localizedDescription ?? "Records could not be loaded. Check your connection and try again."
                    validateSnapshot()
                    if case .ready = state {
                        refreshError = message
                    } else {
                        fail(message)
                    }
                }
            }
        }
        self.task = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if id == operationID {
            self.task = nil
            isRefreshing = false
            // Parent cancellation can finish without a view lifecycle callback.
            if case .loading = state { state = .idle }
        }
    }

    func fail(_ message: String) {
        cancel()
        state = .failed(message)
    }

    func cancel() {
        suspend()
        loadedAt = nil
        refreshError = nil
        state = .idle
    }

    /// Stop unfinished work without discarding a completed in-memory snapshot.
    func suspend() {
        operationID = UUID()
        task?.cancel()
        task = nil
        isRefreshing = false
        if case .loading = state { state = .idle }
    }

    func validateSnapshot() {
        guard case .ready(let plan) = state else { return }
        guard let current = currentContext(), Self.sameInspectionOwner(plan.context, current),
              current.backendIdentity == ImportSessionSnapshot.canonicalBackendIdentity(apiClient.baseURL) else {
            fail("Your connection or pump account changed. Reconnect or validate the account in Settings, then load records again.")
            return
        }
    }

    private static func sameInspectionOwner(_ lhs: ImportSessionSnapshot, _ rhs: ImportSessionSnapshot) -> Bool {
        // A renewed connection can still view the same account's snapshot.
        // This display-only comparison must never authorize a Health import.
        lhs.backendIdentity == rhs.backendIdentity &&
            lhs.configurationRevision == rhs.configurationRevision &&
            lhs.credentialRevision == rhs.credentialRevision &&
            lhs.dataSourceMode == rhs.dataSourceMode
    }
}

enum PreviewError: LocalizedError {
    case upgradeRequired, connectionRequired
    var errorDescription: String? {
        switch self {
        case .upgradeRequired: "This service needs an update to support source data inspection."
        case .connectionRequired: "Connect to the service before inspecting records."
        }
    }
}
