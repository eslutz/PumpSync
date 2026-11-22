import Foundation

struct HealthImportBatch {
    let plan: ImportPlan
    /// The current shared execution owners are reevaluated at Health submission.
    let executionIsValid: @MainActor () -> Bool
    fileprivate init(plan: ImportPlan, executionIsValid: @escaping @MainActor () -> Bool) {
        self.plan = plan
        self.executionIsValid = executionIsValid
    }
}

enum HealthImportPolicy {
    static func authorize(plan: ImportPlan, current: ImportSessionSnapshot, executionIsValid: @escaping @MainActor () -> Bool = { true }) throws -> HealthImportBatch {
        guard plan.context.dataSourceMode == .tandemSource else { throw HealthImportError.previewOnly }
        guard plan.context == current else { throw HealthImportError.staleContext }
        return HealthImportBatch(plan: plan, executionIsValid: executionIsValid)
    }

    static func validate(batch: HealthImportBatch, current: ImportSessionSnapshot?) throws {
        guard let current else { throw HealthImportError.staleContext }
        _ = try authorize(plan: batch.plan, current: current)
    }
}

enum HealthImportError: LocalizedError {
    case previewOnly, unverifiedSource, sourceMismatch, staleContext, invalidWindow, invalidSample, conflictingDuplicate
    var errorDescription: String? {
        switch self {
        case .previewOnly: "Sample data cannot be imported into Apple Health."
        case .unverifiedSource: "PumpSync could not verify the data source."
        case .sourceMismatch: "The data source changed. Start a new sync."
        case .staleContext: "Your Tandem account changed. Start a new sync."
        case .invalidWindow: "Tandem returned an invalid date range."
        case .invalidSample: "Tandem returned unsupported or invalid records."
        case .conflictingDuplicate: "Tandem returned conflicting records for one source identifier. No records were imported."
        }
    }
}
