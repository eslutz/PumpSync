import XCTest
@testable import PumpSync

@MainActor
final class SyncAttemptStoreTests: XCTestCase {
  func testLegacyHistoryDecodesAndRequestLinksAreBoundedAndSanitized() throws {
    let suite = "AttemptLinks.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = #"{"history":[{"operationID":"826024F3-35DF-4A28-A873-8A8364B3790F","trigger":"background","startedAt":0,"stage":"downloading","outcome":"failed","reason":{"requestFailed":{}}}],"active":null}"#
    defaults.set(Data(legacy.utf8), forKey: "sync-attempt-history-v1")
    let store = SyncAttemptStore(defaults: defaults)
    XCTAssertEqual(store.history.count, 1)
    XCTAssertEqual(store.history.first?.requestLinks, [])
    XCTAssertEqual(store.history.first?.droppedRequestLinkCount, 0)
    let operation = UUID()
    store.begin(operationID: operation, trigger: .background)
    let first = UUID().uuidString.lowercased()
    store.recordRequestLink(operationID: UUID(), link: SyncRequestLink(requestID: first, endpoint: .sync))
    XCTAssertEqual(store.active?.requestLinks.count, 0)
    for index in 0..<34 {
      let id = index == 0 ? first : UUID().uuidString.lowercased()
      store.recordRequestLink(operationID: operation, link: SyncRequestLink(requestID: id, endpoint: .sync))
      store.recordRequestLink(operationID: operation, link: SyncRequestLink(requestID: id, endpoint: .sync, backendCorrelationID: "private-account", traceID: "private-token", responseReceived: true))
    }
    XCTAssertEqual(store.active?.requestLinks.count, 32)
    XCTAssertEqual(store.active?.droppedRequestLinkCount, 2)
    XCTAssertNil(store.active?.requestLinks.first?.backendCorrelationID)
    XCTAssertNil(store.active?.requestLinks.first?.traceID)
    store.recordRequestLink(operationID: operation, link: SyncRequestLink(requestID: first, endpoint: .sync, backendCorrelationID: "0HNPA8U2CIRL7:00000002", traceID: "0123456789abcdef0123456789abcdef", responseReceived: true))
    store.finish(operationID: operation, outcome: .completed, reason: .completed)
    let restored = SyncAttemptStore(defaults: defaults)
    XCTAssertEqual(restored.history.first?.requestLinks.count, 32)
    XCTAssertEqual(restored.history.first?.requestLinks.first?.traceID, "0123456789abcdef0123456789abcdef")
    let description = SyncAttemptStore.description(try XCTUnwrap(restored.history.first))
    XCTAssertTrue(description.contains(first))
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

  func testHistoryRetainsTwentyAndActiveAndRejectsPrivateCorrelation() throws {
    let suite = "AttemptBound.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = SyncAttemptStore(defaults: defaults)
    for _ in 0..<25 {
      let id = UUID()
      store.begin(operationID: id, trigger: .manual)
      store.finish(operationID: id, outcome: .blocked, reason: .proofUnavailable)
    }
    XCTAssertEqual(store.history.count, 20)
    let id = UUID()
    store.begin(operationID: id, trigger: .background)
    store.correlate(operationID: id, value: "secret@example.com")
    XCTAssertNil(store.active?.backendCorrelationID)
    store.correlate(operationID: id, value: "0123456789abcdef0123456789abcdef")
    XCTAssertEqual(store.active?.backendCorrelationID, "0123456789abcdef0123456789abcdef")
    store.finish(operationID: UUID(), outcome: .completed, reason: .completed)
    XCTAssertEqual(store.active?.operationID, id)
    XCTAssertEqual(store.history.count, 20)
  }
}
