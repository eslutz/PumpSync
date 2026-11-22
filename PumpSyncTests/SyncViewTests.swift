import XCTest
@testable import PumpSync

@MainActor
final class SyncViewTests: XCTestCase {
  func testForegroundKeepOpenHintAppearsAfterThreeSeconds() {
    let start = Date(timeIntervalSince1970: 100)
    let state = SyncOperationState.running(SyncProgress(phase: .preparing, trigger: .manual, startedAt: start))
    XCTAssertNil(SyncStatusPresentation.make(for: state, now: start.addingTimeInterval(2.9))?.detail)
    XCTAssertEqual(SyncStatusPresentation.make(for: state, now: start.addingTimeInterval(3))?.detail,
                   "Keep PumpSync open while syncing.")
    let background = SyncOperationState.running(SyncProgress(phase: .downloading, trigger: .background, startedAt: start))
    let downloading = SyncStatusPresentation.make(for: background, now: start.addingTimeInterval(60))
    XCTAssertEqual(downloading?.title, "Downloading pump data…")
    XCTAssertNil(downloading?.detail)
    XCTAssertEqual(downloading?.showsProgress, true)
  }

  func testSummaryDistinguishesEmptyDuplicateAndPartialResults() throws {
    let now = Date()
    func result(_ received: Int, _ saved: Int, skipped: Int = 0) -> SyncCompletion {
      SyncCompletion(received: received, saved: saved, permissionSkipped: skipped, completedAt: now)
    }
    XCTAssertEqual(result(0, 0).message, "No new samples")
    XCTAssertEqual(result(3, 0).message, "All samples already imported")
    XCTAssertEqual(result(3, 0, skipped: 2).message, "No samples saved to Apple Health")
    XCTAssertEqual(result(2, 1).message, "1 sample saved to Apple Health")
    XCTAssertEqual(result(1631, 1410).message, "1,410 samples saved to Apple Health")
    let partial = result(10, 3, skipped: 1)
    let status = try XCTUnwrap(SyncStatusPresentation.make(for: .succeeded(partial), now: now))
    let notice = try XCTUnwrap(status.notice)
    XCTAssertEqual(notice, "1 record awaiting Health write access.")
    XCTAssertEqual(status.announcement.components(separatedBy: notice).count, 2)
  }

  func testFailedSyncOnlyShowsRetryDateBeforeDeadline() {
    let date = Date(timeIntervalSince1970: 100)
    let deadline = date.addingTimeInterval(300)
    let failure = SyncOperationState.failed(SyncFailure(message: "Wait.", recovery: .waitAndRetry, retryAfter: deadline))
    XCTAssertTrue(SyncStatusPresentation.make(for: failure, now: date)?.detail?.contains("Try again after") == true)
    XCTAssertEqual(SyncStatusPresentation.make(for: failure, now: deadline)?.detail, "Wait.")
  }

  func testReadinessMessagePromptsForTandemAccount() {
    XCTAssertEqual(
      SyncView.readinessMessage(
        needsReconnect: false,
        hasValidatedCredentials: false,
        hasAnyHealthWritePermission: false
      ),
      "Sign in to your Tandem account to sync your pump history."
    )
  }

  func testReadinessMessagePromptsForHealthWriteAccessAfterCredentialsAreValidated() {
    XCTAssertEqual(
      SyncView.readinessMessage(
        needsReconnect: false,
        hasValidatedCredentials: true,
        hasAnyHealthWritePermission: false
      ),
      "Enable at least one Apple Health write permission before syncing."
    )
  }

  func testLegacyAccountRequiresExplicitReconnectBeforeHealthSetup() {
    XCTAssertEqual(SyncView.readinessMessage(
      needsReconnect: true, hasValidatedCredentials: false, hasAnyHealthWritePermission: false
    ), "Reconnect your saved account to sync directly with Tandem.")
  }

  func testReadinessMessageIsNilWhenReady() {
    XCTAssertNil(SyncView.readinessMessage(
      needsReconnect: false,
      hasValidatedCredentials: true,
      hasAnyHealthWritePermission: true
    ))
  }
}
