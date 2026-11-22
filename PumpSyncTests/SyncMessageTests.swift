import XCTest
@testable import PumpSync

final class SyncMessageTests: XCTestCase {
  func testOnlyActionableEventsProduceCrossTabMessages() {
    let now = Date()
    XCTAssertNil(SyncMessage(for: .idle))
    XCTAssertNil(SyncMessage(for: .running(SyncProgress(phase: .downloading, trigger: .manual, startedAt: now))))
    XCTAssertNil(SyncMessage(for: .succeeded(SyncCompletion(received: 10, saved: 2, completedAt: now))))
    XCTAssertNil(SyncMessage(for: .succeeded(SyncCompletion(received: 10, saved: 2, gapBefore: now, completedAt: now))))
    XCTAssertEqual(SyncMessage(for: .failed(SyncFailure(message: "Retry.", recovery: .retry))), .failed)
    XCTAssertEqual(SyncMessage(for: .succeeded(SyncCompletion(received: 10, saved: 2, permissionSkipped: 1, completedAt: now))), .healthAccess)
  }
}
