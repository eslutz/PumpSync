import XCTest
@testable import PumpSync

final class DashboardViewTests: XCTestCase {
  func testDashboardMessagesShowsOnlyOneUnauthenticatedSyncPrompt() {
    let messages = DashboardView.dashboardMessages(
      isSignedIn: false,
      syncMessage: "Sign in before syncing.",
      authErrorMessage: nil,
      lastSyncErrorMessage: nil
    )

    XCTAssertEqual(messages, ["Sign in before syncing."])
  }
}
