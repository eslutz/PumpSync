import XCTest
@testable import PumpSync

final class SyncViewTests: XCTestCase {
  func testReadinessMessagePromptsForSignInFirst() {
    XCTAssertEqual(
      SyncView.readinessMessage(isSignedIn: false, hasStoredCredentials: false),
      "Sign in from Settings before syncing."
    )
  }

  func testReadinessMessagePromptsForCredentialsAfterSignIn() {
    XCTAssertEqual(
      SyncView.readinessMessage(isSignedIn: true, hasStoredCredentials: false),
      "Add Tandem credentials in Settings before syncing."
    )
  }

  func testReadinessMessageIsNilWhenReady() {
    XCTAssertNil(SyncView.readinessMessage(isSignedIn: true, hasStoredCredentials: true))
  }
}
