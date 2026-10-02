import Foundation

struct HealthImportBatch {
    let plan: ImportPlan
    fileprivate init(plan: ImportPlan) { self.plan = plan }
}

enum HealthImportPolicy {
    static func authorize(plan: ImportPlan, current: ImportSessionSnapshot) throws -> HealthImportBatch {
        guard plan.context.dataSourceMode == .tandemSource else { throw HealthImportError.previewOnly }
        guard plan.context == current else { throw HealthImportError.staleContext }
        return HealthImportBatch(plan: plan)
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
        case .previewOnly: "This service supplies sample data. Open Sample Preview instead."
        case .unverifiedSource: "The service could not verify the data source. Upgrade the backend before importing."
        case .sourceMismatch: "The service data source changed. Reconnect before importing."
        case .staleContext: "Your connection or pump credentials changed. Start a new sync."
        case .invalidWindow: "The service returned an invalid date range. Update the backend and try again."
        case .invalidSample: "The service returned unsupported or invalid records. Update the backend before importing."
        case .conflictingDuplicate: "The service returned conflicting records for one source identifier. No records were imported."
        }
    }
}
