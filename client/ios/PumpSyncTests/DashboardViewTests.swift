import XCTest
@testable import PumpSync

final class DashboardViewTests: XCTestCase {
  func testDashboardMessagesShowProductionReadinessPrompts() {
    let messages = DashboardView.dashboardMessages(
      isSignedIn: false,
      hasStoredCredentials: false,
      isHealthAuthorized: false
    )

    XCTAssertEqual(messages, ["Sign in from Settings before syncing."])
  }

  func testDashboardMessagesHideDeveloperErrorsWhenReady() {
    let messages = DashboardView.dashboardMessages(
      isSignedIn: true,
      hasStoredCredentials: true,
      isHealthAuthorized: true
    )

    XCTAssertEqual(messages, [])
  }
}
