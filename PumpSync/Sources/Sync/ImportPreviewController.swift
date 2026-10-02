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
            diagnostics?.record(source: .sync, title: "Import preview", message: "purpose=\(purpose.rawValue) \(summary)")
        }
    }
    private let purpose: ImportPreviewPurpose
    private let diagnostics: DiagnosticsLogStore?
    private let apiClient: PumpSyncAPIClient
    private let authService: AuthService
    private var operationID = UUID()
    private var task: Task<Void, Never>?
    private let currentContext: () -> ImportSessionSnapshot?

    init(apiClient: PumpSyncAPIClient, authService: AuthService, purpose: ImportPreviewPurpose = .real, diagnostics: DiagnosticsLogStore? = nil, currentContext: @escaping () -> ImportSessionSnapshot?) {
        self.purpose = purpose
        self.diagnostics = diagnostics
        self.apiClient = apiClient
        self.authService = authService
        self.currentContext = currentContext
    }

    func load(request: TandemSyncRequest, context: ImportSessionSnapshot, concentration: InsulinConcentration) async {
        cancel()
        let id = operationID
        state = .loading
        let task = Task { @MainActor in
            var submittedToken: String?
            do {
                let capabilities = try await apiClient.capabilities()
                guard capabilities.supportsImportPreview else { throw PreviewError.upgradeRequired }
                guard capabilities.dataSourceMode == context.dataSourceMode else { throw HealthImportError.sourceMismatch }
                guard id == operationID, !Task.isCancelled else { return }
                guard context == currentContext() else { state = .failed("Your connection or pump account changed. Reconnect or validate the account, then retry Preview."); return }
                guard let token = await authService.accessTokenRecoveringIfNeeded() else { throw PreviewError.connectionRequired }
                guard !Task.isCancelled, id == operationID else { return }
                guard context == currentContext() else { state = .failed("Your connection or pump account changed. Reconnect or validate the account, then retry Preview."); return }
                submittedToken = token
                let response = try await apiClient.previewTandem(request, accessToken: token)
                guard !Task.isCancelled, id == operationID else { return }
                guard context == currentContext(), context.backendIdentity == ImportSessionSnapshot.canonicalBackendIdentity(apiClient.baseURL) else { state = .failed("Your connection or pump account changed. Reconnect or validate the account, then retry Preview."); return }
                let plan = try ImportPlanner.makePlan(response: response, context: context, concentration: concentration)
                state = .ready(plan)
            } catch {
                guard !Task.isCancelled, id == operationID else { return }
                // Backend messages can contain provider identifiers. Keep preview errors local.
                if let error = error as? APIClientError, error.isAuthenticationFailure {
                    if authService.session?.accessToken == submittedToken { authService.clearSessionForAuthenticationFailure() }
                    state = .failed("The preview connection expired. Reconnect to the service and try again.")
                }
                else if error is HealthImportError { state = .failed("The service returned unverified or invalid records. Reconnect or update the backend before previewing.") }
                else if let error = error as? PreviewError { state = .failed(error.localizedDescription) }
                else { state = .failed("Preview could not be downloaded. Check the connection and try again.") }
            }
        }
        self.task = task
        await task.value
        if id == operationID { self.task = nil }
    }

    func fail(_ message: String) {
        cancel()
        state = .failed(message)
    }

    func cancel() {
        operationID = UUID()
        task?.cancel()
        task = nil
        state = .idle
    }
}

enum ImportPreviewPurpose: String { case real, sample }

enum PreviewError: LocalizedError {
    case upgradeRequired, connectionRequired, invalidCredentials
    var errorDescription: String? {
        switch self {
        case .upgradeRequired: "This service needs an update to support Import Preview."
        case .connectionRequired: "Connect to the service before previewing records."
        case .invalidCredentials: "The sample account could not be validated. Check the details and try again."
        }
    }
}
