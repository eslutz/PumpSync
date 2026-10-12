import XCTest
@testable import PumpSync

@MainActor
final class SyncAttemptStoreTests: XCTestCase {
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
    XCTAssertEqual(restarted.history.first?.durationSeconds, 2)
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
