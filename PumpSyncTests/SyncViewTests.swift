import XCTest
@testable import PumpSync

final class SyncViewTests: XCTestCase {
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
