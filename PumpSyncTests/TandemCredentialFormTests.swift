import XCTest
@testable import PumpSync

@MainActor
final class TandemCredentialFormTests: XCTestCase {
  func testAbandonedValidationDoesNotCommitAndCannotClearNewRequestsBusyState() async {
    let lifetime = CredentialValidationLifetime()
    var oldContinuation: CheckedContinuation<Void, Never>?
    var newContinuation: CheckedContinuation<Void, Never>?
    var saved = false
    lifetime.start {
      await withCheckedContinuation { oldContinuation = $0 }
      if !Task.isCancelled { saved = true }
    }
    while oldContinuation == nil { await Task.yield() }
    lifetime.cancel()
    XCTAssertFalse(lifetime.isRunning)
    lifetime.start {
      await withCheckedContinuation { newContinuation = $0 }
    }
    while newContinuation == nil { await Task.yield() }
    oldContinuation?.resume()
    for _ in 0..<10 { await Task.yield() }
    XCTAssertFalse(saved)
    XCTAssertTrue(lifetime.isRunning)
    newContinuation?.resume()
    while lifetime.isRunning { await Task.yield() }
  }

  func testActionStateForNewCredentialsRequiresAllFields() {
    XCTAssertEqual(TandemCredentialForm.actionState(hasStoredCredentials: false, usernameChanged: false, regionChanged: false, password: ""), .saveDisabled)
    XCTAssertEqual(TandemCredentialForm.actionState(hasStoredCredentials: false, usernameChanged: true, regionChanged: false, password: "secret"), .save)
  }

  func testStoredUnchangedCredentialsOfferRemoval() {
    XCTAssertEqual(TandemCredentialForm.actionState(hasStoredCredentials: true, usernameChanged: false, regionChanged: false, password: ""), .remove)
  }

  func testStoredEditedCredentialsRequirePasswordBeforeSave() {
    XCTAssertEqual(TandemCredentialForm.actionState(hasStoredCredentials: true, usernameChanged: true, regionChanged: false, password: ""), .saveDisabled)
    XCTAssertEqual(TandemCredentialForm.actionState(hasStoredCredentials: true, usernameChanged: false, regionChanged: true, password: ""), .saveDisabled)
    XCTAssertEqual(TandemCredentialForm.actionState(hasStoredCredentials: true, usernameChanged: true, regionChanged: false, password: "secret"), .save)
  }

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
