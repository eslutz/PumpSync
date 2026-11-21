import XCTest
@testable import PumpSync

@MainActor
final class SyncViewTests: XCTestCase {
  func testPreparingPresentationExplainsDirectConnectionAfterThreeSeconds() throws {
    let startedAt = Date(timeIntervalSince1970: 100)
    let state = SyncOperationState.running(
      SyncProgress(phase: .preparing, trigger: .manual, startedAt: startedAt)
    )

    let presentation = try XCTUnwrap(
      SyncStatusPresentation.make(for: state, now: startedAt.addingTimeInterval(3))
    )

    XCTAssertEqual(presentation.title, "Preparing sync…")
    XCTAssertEqual(presentation.detail, "Keep PumpSync open while it connects to Tandem.")
    XCTAssertNil(presentation.action)
    XCTAssertNil(presentation.actionTitle)
    XCTAssertTrue(presentation.showsProgress)
  }

  func testPreparingPresentationUsesShortCopyBeforeThreeSeconds() throws {
    let startedAt = Date(timeIntervalSince1970: 100)
    let state = SyncOperationState.running(
      SyncProgress(phase: .preparing, trigger: .manual, startedAt: startedAt)
    )

    let presentation = try XCTUnwrap(
      SyncStatusPresentation.make(for: state, now: startedAt.addingTimeInterval(2.9))
    )

    XCTAssertEqual(presentation.detail, "Connecting to Tandem…")
  }

  func testRunningPresentationsDescribeDownloadingAndHealthUpdate() throws {
    let startedAt = Date(timeIntervalSince1970: 100)
    let downloading = try XCTUnwrap(SyncStatusPresentation.make(
      for: .running(SyncProgress(phase: .downloading, trigger: .manual, startedAt: startedAt)),
      now: startedAt
    ))
    let updatingHealth = try XCTUnwrap(SyncStatusPresentation.make(
      for: .running(SyncProgress(phase: .updatingHealth, trigger: .manual, startedAt: startedAt)),
      now: startedAt
    ))

    XCTAssertEqual(downloading.title, "Downloading pump data…")
    XCTAssertEqual(downloading.detail, "Retrieving available pump history.")
    XCTAssertEqual(updatingHealth.title, "Updating Apple Health…")
    XCTAssertEqual(updatingHealth.detail, "Saving new pump samples to Apple Health.")
  }

  func testActiveBackgroundWorkIsDiscoverableWhileIdleHasNoResult() {
    let now = Date(timeIntervalSince1970: 100)

    XCTAssertTrue(SyncStatusPresentation.make(
      for: .running(SyncProgress(phase: .preparing, trigger: .background, startedAt: now)),
      now: now
    )?.showsProgress == true)
    XCTAssertNil(SyncStatusPresentation.make(for: .idle, now: now))
  }

  func testSuccessPresentationHasNoTransientDismissal() throws {
    let state = SyncOperationState.succeeded(
      SyncCompletion(message: "Imported 4 new samples.", completedAt: Date(timeIntervalSince1970: 100))
    )

    let presentation = try XCTUnwrap(SyncStatusPresentation.make(for: state, now: Date()))

    XCTAssertEqual(presentation.title, "Sync complete")
    XCTAssertEqual(presentation.detail, "Imported 4 new samples.")
    XCTAssertEqual(presentation.systemImage, "checkmark.circle.fill")
    XCTAssertNil(presentation.action)
  }

  func testFailurePresentationMapsEveryRecoveryAction() throws {
    let now = Date(timeIntervalSince1970: 100)
    let retry = try XCTUnwrap(SyncStatusPresentation.make(
      for: .failed(SyncFailure(message: "Try later.", recovery: .retry)),
      now: now
    ))
    let settings = try XCTUnwrap(SyncStatusPresentation.make(
      for: .failed(SyncFailure(message: "Fix settings.", recovery: .openSettings)),
      now: now
    ))
    let wait = try XCTUnwrap(SyncStatusPresentation.make(
      for: .failed(SyncFailure(message: "Wait.", recovery: .waitAndRetry)),
      now: now
    ))
    let dismiss = try XCTUnwrap(SyncStatusPresentation.make(
      for: .failed(SyncFailure(message: "Could not sync.", recovery: .none)),
      now: now
    ))

    XCTAssertEqual(retry.actionTitle, "Try Again")
    XCTAssertEqual(retry.action, .retry)
    XCTAssertEqual(settings.actionTitle, "Open Settings")
    XCTAssertEqual(settings.action, .openSettings)
    XCTAssertEqual(wait.actionTitle, "Try Again Later")
    XCTAssertEqual(wait.action, .retry)
    XCTAssertNil(dismiss.actionTitle)
    XCTAssertNil(dismiss.action)
  }

  func testSyncPhaseMessagesExplainLongRunningActivation() {
    XCTAssertEqual(SyncPhase.preparing.message, "Preparing sync…")
    XCTAssertEqual(SyncPhase.downloading.message, "Downloading pump data…")
    XCTAssertEqual(SyncPhase.updatingHealth.message, "Updating Apple Health…")
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
