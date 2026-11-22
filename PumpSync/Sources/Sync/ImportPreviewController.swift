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
            let preview: ImportPreviewDiagnostic
            switch state {
            case .idle:
                summary = "state=idle"
                preview = ImportPreviewDiagnostic(status: .idle)
            case .loading:
                summary = "state=loading"
                preview = ImportPreviewDiagnostic(status: .loading)
            case .ready(let plan):
                summary = "state=ready source=\(plan.context.dataSourceMode.rawValue) count=\(plan.downloadedRecordCount)"
                preview = ImportPreviewDiagnostic(status: .ready, source: plan.context.dataSourceMode, recordCount: plan.downloadedRecordCount)
            case .failed:
                summary = "state=failed reason=previewUnavailable"
                preview = ImportPreviewDiagnostic(status: .failed)
            }
            diagnostics?.record(source: .sync, title: "Import preview", message: "purpose=real \(summary)", importPreview: preview)
        }
    }
    private let diagnostics: DiagnosticsLogStore?
    private let dataSource: any TandemDataSource
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

    init(dataSource: any TandemDataSource, diagnostics: DiagnosticsLogStore? = nil, currentContext: @escaping () -> ImportSessionSnapshot?) {
        self.diagnostics = diagnostics
        self.dataSource = dataSource
        self.currentContext = currentContext
    }

    func load(request: TandemSyncRequest, context: ImportSessionSnapshot, concentration: InsulinConcentration) async {
        validateSnapshot()
        suspend()
        if case .ready(let plan) = state, plan.context == context {
            isRefreshing = true
        } else {
            cancel()
            state = .loading
        }
        refreshError = nil
        let id = operationID
        let task = Task { @MainActor in
            do {
                guard !Task.isCancelled, id == operationID else { return }
                guard context == currentContext() else { fail("Your Tandem account changed. Load the records again."); return }
                let response = try await dataSource.load(request)
                guard !Task.isCancelled, id == operationID else { return }
                guard context == currentContext() else { fail("Your Tandem account changed. Load the records again."); return }
                let plan = try ImportPlanner.makePlan(response: response, context: context, concentration: concentration)
                loadedAt = Date()
                state = .ready(plan)
            } catch {
                guard !Task.isCancelled, id == operationID else { return }
                if error is HealthImportError {
                    fail("Tandem returned records that could not be verified.")
                } else {
                    let message = (error as? DirectTandemError)?.localizedDescription ?? "Records could not be loaded. Try again."
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
        guard plan.context == currentContext() else {
            fail("Your Tandem account changed. Load the records again.")
            return
        }
    }
}
