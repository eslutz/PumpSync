import XCTest
@testable import PumpSync

final class TandemCredentialFormTests: XCTestCase {
  func testSkipsRevalidationWhenCredentialsExactlyMatchLastValidatedSave() {
    let credentials = TandemCredentials(username: "demo@pumpsync.app", password: "hunter2", region: "us")

    XCTAssertTrue(TandemCredentialForm.shouldSkipRevalidation(current: credentials, lastValidated: credentials))
  }

  func testDoesNotSkipWhenThereIsNoPriorValidatedSave() {
    let credentials = TandemCredentials(username: "demo@pumpsync.app", password: "hunter2", region: "us")

    XCTAssertFalse(TandemCredentialForm.shouldSkipRevalidation(current: credentials, lastValidated: nil))
  }

  func testDoesNotSkipWhenUsernameChanged() {
    let lastValidated = TandemCredentials(username: "demo@pumpsync.app", password: "hunter2", region: "us")
    let current = TandemCredentials(username: "someone-else@pumpsync.app", password: "hunter2", region: "us")

    XCTAssertFalse(TandemCredentialForm.shouldSkipRevalidation(current: current, lastValidated: lastValidated))
  }

  func testDoesNotSkipWhenPasswordChanged() {
    let lastValidated = TandemCredentials(username: "demo@pumpsync.app", password: "hunter2", region: "us")
    let current = TandemCredentials(username: "demo@pumpsync.app", password: "a-new-password", region: "us")

    XCTAssertFalse(TandemCredentialForm.shouldSkipRevalidation(current: current, lastValidated: lastValidated))
  }

  func testDoesNotSkipWhenOnlyRegionChanged() {
    // Region alone selects a different Tandem login endpoint, so even a
    // region-only change must still hit the backend.
    let lastValidated = TandemCredentials(username: "demo@pumpsync.app", password: "hunter2", region: "us")
    let current = TandemCredentials(username: "demo@pumpsync.app", password: "hunter2", region: "eu")

    XCTAssertFalse(TandemCredentialForm.shouldSkipRevalidation(current: current, lastValidated: lastValidated))
  }
}
