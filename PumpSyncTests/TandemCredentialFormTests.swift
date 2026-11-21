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
    XCTAssertEqual(TandemCredentialForm.actionState(username: "fixture", password: ""), .saveDisabled)
    XCTAssertEqual(TandemCredentialForm.actionState(username: " \n ", password: "current-password"), .saveDisabled)
    XCTAssertEqual(TandemCredentialForm.actionState(username: "fixture", password: "current-password"), .save)
  }

  func testEditingCurrentLoginNeverTurnsSaveIntoCredentialRemoval() {
    XCTAssertEqual(TandemCredentialForm.actionState(username: "saved-account", password: ""), .saveDisabled)
    XCTAssertEqual(TandemCredentialForm.actionState(username: "saved-account", password: "updated-tandem-password"), .save)
  }

}
