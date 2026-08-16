import XCTest
@testable import PumpSync

@MainActor
final class SyncViewTests: XCTestCase {
  func testPreparingPresentationExplainsMeasuredColdStartAfterThreeSeconds() throws {
    let startedAt = Date(timeIntervalSince1970: 100)
    let state = SyncOperationState.running(
      SyncProgress(phase: .preparing, trigger: .manual, startedAt: startedAt)
    )

    let presentation = try XCTUnwrap(
      SyncStatusPresentation.make(for: state, now: startedAt.addingTimeInterval(3))
    )

    XCTAssertEqual(presentation.title, "Starting secure service…")
    XCTAssertEqual(presentation.detail, "This can take about 30 seconds after inactivity. Keep PumpSync open.")
    XCTAssertEqual(presentation.action, .viewSync)
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

    XCTAssertEqual(presentation.detail, "Connecting securely…")
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

  func testBackgroundProgressAndSuccessAreNotPresented() {
    let now = Date(timeIntervalSince1970: 100)

    XCTAssertNil(SyncStatusPresentation.make(
      for: .running(SyncProgress(phase: .preparing, trigger: .background, startedAt: now)),
      now: now
    ))
    XCTAssertNil(SyncStatusPresentation.make(for: .idle, now: now))
  }

  func testSuccessPresentationAutoDismissesAfterEightSeconds() throws {
    let state = SyncOperationState.succeeded(
      SyncCompletion(message: "Imported 4 new samples.", completedAt: Date(timeIntervalSince1970: 100))
    )

    let presentation = try XCTUnwrap(SyncStatusPresentation.make(for: state, now: Date()))

    XCTAssertEqual(presentation.title, "Sync complete")
    XCTAssertEqual(presentation.detail, "Imported 4 new samples.")
    XCTAssertEqual(presentation.systemImage, "checkmark.circle.fill")
    XCTAssertNil(presentation.action)
    XCTAssertEqual(presentation.autoDismissAfter, 8)
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
    XCTAssertEqual(wait.actionTitle, "Dismiss")
    XCTAssertEqual(wait.action, .dismiss)
    XCTAssertEqual(dismiss.actionTitle, "Dismiss")
    XCTAssertEqual(dismiss.action, .dismiss)
  }

  func testSyncPhaseMessagesExplainLongRunningActivation() {
    XCTAssertEqual(SyncPhase.preparing.message, "Starting secure service…")
    XCTAssertEqual(SyncPhase.downloading.message, "Downloading pump data…")
    XCTAssertEqual(SyncPhase.updatingHealth.message, "Updating Apple Health…")
  }

  func testSyncIconRotationStaysAtZeroWhenNotSyncing() {
    let startDate = Date(timeIntervalSince1970: 100)
    let laterDate = startDate.addingTimeInterval(5)

    XCTAssertEqual(
      SyncButtonIconRotation.angle(
        isSyncing: false,
        startDate: startDate,
        currentDate: laterDate
      ),
      0
    )
  }

  func testSyncIconRotationAdvancesWhileSyncing() {
    let startDate = Date(timeIntervalSince1970: 100)
    let currentDate = startDate.addingTimeInterval(0.2)

    XCTAssertEqual(
      SyncButtonIconRotation.angle(
        isSyncing: true,
        startDate: startDate,
        currentDate: currentDate,
        revolutionDuration: 0.8
      ),
      90,
      accuracy: 0.001
    )
  }

  func testReadinessMessagePromptsForSignInFirst() {
    XCTAssertNil(SyncView.readinessMessage(
      isBackendConnected: false,
      hasValidatedCredentials: false,
      hasAnyHealthWritePermission: false
    ))
  }

  func testConnectionPresentationExplainsSessionRecovery() {
    XCTAssertEqual(
      SyncView.connectionStatus(isSignedIn: false, isConnecting: true),
      "Connecting to PumpSync…"
    )
    XCTAssertEqual(
      SyncView.readinessMessage(
        isBackendConnected: false,
        isConnecting: true,
        hasValidatedCredentials: true,
        hasAnyHealthWritePermission: true
      ),
      "Restoring your secure connection. Sync will start automatically when ready."
    )
    XCTAssertEqual(
      SyncView.syncButtonTitle(
        isSyncing: false,
        isConnecting: true,
        hasCompletedInitialSync: true,
        initialImportRange: .pastTwoDays
      ),
      "Connecting…"
    )
  }

  func testReadinessMessagePromptsForSavedCredentialsAfterSignIn() {
    XCTAssertEqual(
      SyncView.readinessMessage(
        isBackendConnected: true,
        hasValidatedCredentials: false,
        hasAnyHealthWritePermission: false
      ),
      "Save your pump account credentials in Settings before syncing."
    )
  }

  func testReadinessMessagePromptsForHealthWriteAccessAfterCredentialsAreValidated() {
    XCTAssertEqual(
      SyncView.readinessMessage(
        isBackendConnected: true,
        hasValidatedCredentials: true,
        hasAnyHealthWritePermission: false
      ),
      "Enable at least one Apple Health write permission before syncing."
    )
  }

  func testReadinessMessageIsNilWhenReady() {
    XCTAssertNil(SyncView.readinessMessage(
      isBackendConnected: true,
      hasValidatedCredentials: true,
      hasAnyHealthWritePermission: true
    ))
  }
}
