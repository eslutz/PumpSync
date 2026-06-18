import XCTest
@testable import PumpSync

final class SyncViewTests: XCTestCase {
  func testReadinessMessagePromptsForSignInFirst() {
    XCTAssertNil(SyncView.readinessMessage(
      isBackendConnected: false,
      hasValidatedCredentials: false,
      hasAnyHealthWritePermission: false
    ))
  }

  func testReadinessMessagePromptsForValidatedCredentialsAfterSignIn() {
    XCTAssertEqual(
      SyncView.readinessMessage(
        isBackendConnected: true,
        hasValidatedCredentials: false,
        hasAnyHealthWritePermission: false
      ),
      "Validate Tandem credentials in Settings before syncing."
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
