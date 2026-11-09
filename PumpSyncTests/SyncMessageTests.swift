import XCTest
@testable import PumpSync

final class SyncMessageTests: XCTestCase {
  func testRoutineStatesDoNotProduceFloatingMessages() {
    let now = Date(timeIntervalSince1970: 100)
    let states: [SyncOperationState] = [
      .idle,
      .running(SyncProgress(phase: .downloading, trigger: .manual, startedAt: now)),
      .succeeded(SyncCompletion(message: "Imported 4 samples.", completedAt: now)),
      .succeeded(SyncCompletion(message: "Imported 4 samples.", completedAt: now, notice: " \n "))
    ]
    for state in states {
      XCTAssertNil(SyncMessage.make(for: state, id: UUID()))
    }
  }

  func testImportantCompletionNoticeIsNotReplacedByRoutineSuccessText() throws {
    let state = SyncOperationState.succeeded(SyncCompletion(
      message: "Imported 4 samples.", completedAt: Date(), notice: "Some older records were unavailable."
    ))
    let message = try XCTUnwrap(SyncMessage.make(for: state, id: UUID()))
    XCTAssertEqual(message.detail, "Some older records were unavailable.")
    XCTAssertNil(message.action)
    XCTAssertNil(message.actionTitle)
  }

  func testFailureRetainsActionAndOccurrenceIdentity() throws {
    let state = SyncOperationState.failed(SyncFailure(message: "Review your connection.", recovery: .openSettings))
    let eventID = UUID()
    let first = try XCTUnwrap(SyncMessage.make(for: state, id: eventID))
    XCTAssertEqual(first.action, .openSettings)
    XCTAssertEqual(first.actionTitle, "Connection Settings")
    XCTAssertEqual(first, SyncMessage.make(for: state, id: eventID))
    let repeatedFailure = try XCTUnwrap(SyncMessage.make(for: state, id: UUID()))
    XCTAssertNotEqual(first.id, repeatedFailure.id, "Dismissing one occurrence must not hide a later identical error.")
    XCTAssertEqual(first.detail, repeatedFailure.detail)
  }
}
