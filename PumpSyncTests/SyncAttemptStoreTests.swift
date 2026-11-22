import XCTest
@testable import PumpSync

@MainActor
final class SyncAttemptStoreTests: XCTestCase {
  func testLegacyHistoryDecodesAndRequestLinksAreBoundedAndSanitized() throws {
    let suite = "AttemptLinks.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let request = UUID().uuidString
    let link: [String: Any] = ["requestID": request, "endpoint": "sync", "responseReceived": true,
                               "backendCorrelationID": "private-account", "traceID": "private-token"]
    let legacy: [String: Any] = [
      "operationID": UUID().uuidString, "trigger": "background", "startedAt": 0,
      "stage": "recovering", "outcome": "blocked", "reason": ["recovery": ["_0": "missingEntitlement"]],
      "backendCorrelationID": "secret@example.com",
      "requestLinks": Array(repeating: link, count: 34)
    ]
    defaults.set(try JSONSerialization.data(withJSONObject: ["history": [legacy]]), forKey: "sync-attempt-history-v1")
    let store = SyncAttemptStore(defaults: defaults)
    let attempt = try XCTUnwrap(store.history.first)
    XCTAssertEqual(attempt.reason, .recovery(.missingEntitlement))
    XCTAssertEqual(attempt.requestLinks.count, 32)
    XCTAssertNil(attempt.requestLinks.first?.backendCorrelationID)
    XCTAssertNil(attempt.requestLinks.first?.traceID)
    XCTAssertNil(attempt.backendCorrelationID)
    let description = SyncAttemptStore.description(attempt)
    XCTAssertTrue(description.contains(request))
    XCTAssertFalse(description.contains("private-"))
  }

  func testRestartInterruptsActiveAttempt() throws {
    let suite = "AttemptRestart.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SyncAttemptStore(defaults: defaults)
    let id = UUID()
    store.begin(operationID: id, trigger: .background, at: Date(timeIntervalSince1970: 10))
    store.advance(operationID: id, stage: .recovering)
    let restarted = SyncAttemptStore(defaults: defaults, now: Date(timeIntervalSince1970: 12))
    XCTAssertNil(restarted.active)
    XCTAssertEqual(restarted.history.first?.operationID, id)
    XCTAssertEqual(restarted.history.first?.outcome, .interrupted)
    XCTAssertEqual(restarted.history.first?.reason, .processInterrupted)
    XCTAssertNil(restarted.history.first?.durationSeconds)
    XCTAssertNil(restarted.history.first?.completedAt)
    XCTAssertEqual(restarted.history.first?.interruptionDetectedAt, Date(timeIntervalSince1970: 12))
  }

  func testRestartPreservesEachImportCheckpointAndCountsWithoutInventingDuration() throws {
    for checkpoint in [SyncImportCheckpoint.healthSaveStarted, .healthSaveCompleted, .ledgerCommitStarted, .ledgerCommitCompleted, .metadataCommitted] {
      let suite = "Checkpoint.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let store = SyncAttemptStore(defaults: defaults)
      let id = UUID()
      store.begin(operationID: id, trigger: .background, at: Date(timeIntervalSince1970: 10))
      store.advance(operationID: id, stage: .updatingHealth, at: Date(timeIntervalSince1970: 11))
      store.recordCounts(operationID: id, returned: 12, imported: 4, permissionSkipped: 0)
      store.checkpoint(operationID: UUID(), checkpoint: .metadataCommitted)
      XCTAssertNil(store.active?.importCheckpoint)
      store.checkpoint(operationID: id, checkpoint: checkpoint, at: Date(timeIntervalSince1970: 12))
      let restarted = SyncAttemptStore(defaults: defaults, now: Date(timeIntervalSince1970: 60_000))
      let attempt = try XCTUnwrap(restarted.history.first)
      XCTAssertEqual(attempt.importCheckpoint, checkpoint)
      XCTAssertEqual(attempt.lastObservedAt, Date(timeIntervalSince1970: 12))
      XCTAssertEqual(attempt.importedCount, 4)
      XCTAssertNotNil(attempt.protectedDataAvailable)
      XCTAssertNil(attempt.durationSeconds)
      XCTAssertTrue(SyncAttemptStore.description(attempt).contains("durationSeconds=unknown"))
      XCTAssertEqual(SyncAttemptStore(defaults: defaults).history, restarted.history)
    }
  }

  func testHistoryRetainsTwentyAndActive() throws {
    let suite = "AttemptBound.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SyncAttemptStore(defaults: defaults)
    for _ in 0..<25 {
      let id = UUID()
      store.begin(operationID: id, trigger: .manual)
      store.finish(operationID: id, outcome: .blocked, reason: .healthPermission)
    }
    XCTAssertEqual(store.history.count, 20)
    let id = UUID()
    store.begin(operationID: id, trigger: .background)
    store.finish(operationID: UUID(), outcome: .completed, reason: .completed)
    XCTAssertEqual(store.active?.operationID, id)
    XCTAssertEqual(store.history.count, 20)
  }
}
