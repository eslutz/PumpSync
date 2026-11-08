import XCTest
@testable import PumpSync

final class DiagnosticEventGroupTests: XCTestCase {
    func testOperationAppearsOnceWithLatestOutcomeAndAllRetainedStages() throws {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 100)
        var attempt = SyncAttempt(operationID: id, trigger: .manual, startedAt: start, stage: .recovering)
        let first = DiagnosticEntry(timestamp: start, source: .sync, severity: .info,
                                    title: "Owned sync attempt", message: "first", syncAttempt: attempt)
        attempt.stage = .downloading
        let second = DiagnosticEntry(timestamp: start.addingTimeInterval(1), source: .sync, severity: .info,
                                     title: "Owned sync attempt", message: "second", syncAttempt: attempt)
        attempt.outcome = .interrupted
        attempt.reason = .processInterrupted
        let final = DiagnosticEntry(timestamp: start.addingTimeInterval(2), source: .sync, severity: .info,
                                    title: "Owned sync attempt", message: "final", syncAttempt: attempt)
        let groups = DiagnosticEventGroup.make(from: [second, first, final])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].title, "Manual sync interrupted")
        XCTAssertEqual(groups[0].entries.map(\.id), [final.id, second.id, first.id])
        XCTAssertTrue(try XCTUnwrap(groups[0].summary).contains("actual end time is unknown"))
    }

    func testLegacyEntriesStaySeparateAndOperationsDoNotMergeAcrossAccounts() {
        let date = Date()
        let legacy = (0..<2).map { i in
            DiagnosticEntry(timestamp: date.addingTimeInterval(Double(i)), source: .sync, severity: .info,
                            title: "Sync completed", message: nil)
        }
        let operations = (0..<2).map { i in
            DiagnosticEntry(timestamp: date.addingTimeInterval(Double(i + 2)), source: .sync, severity: .info,
                            title: "Owned sync attempt", message: nil,
                            syncAttempt: SyncAttempt(operationID: UUID(), trigger: .background, startedAt: date, stage: .recovering))
        }
        XCTAssertEqual(DiagnosticEventGroup.make(from: legacy + operations).count, 4)
    }

    func testExportSerializesOperationOnceAndRetainsRedaction() {
        let attempt = SyncAttempt(operationID: UUID(), trigger: .manual, startedAt: Date(), stage: .recovering)
        let entry = DiagnosticEntry(source: .sync, severity: .info, title: "Owned sync attempt",
                                    message: SyncAttemptStore.description(attempt), syncAttempt: attempt)
        let text = DiagnosticPresentation.export(entry)
        XCTAssertEqual(text.components(separatedBy: "operation=").count - 1, 1)
        let legacy = DiagnosticEntry(source: .auth, severity: .error, title: "Connection failed", message: "password=secret-marker")
        XCTAssertFalse(DiagnosticPresentation.export(legacy).contains("secret-marker"))
    }

    func testCountOrderDoesNotInventDispositions() {
        var attempt = SyncAttempt(operationID: UUID(), trigger: .manual, startedAt: Date(), stage: .terminal, outcome: .completed)
        attempt.returnedCount = 10
        attempt.importedCount = 12
        let entry = DiagnosticEntry(source: .sync, severity: .info, title: "Owned sync attempt", message: nil, syncAttempt: attempt)
        XCTAssertEqual(DiagnosticPresentation.summary(for: entry), "10 records received · 12 samples saved")
        XCTAssertFalse(DiagnosticPresentation.summary(for: entry)!.contains("duplicate"))
    }
}
