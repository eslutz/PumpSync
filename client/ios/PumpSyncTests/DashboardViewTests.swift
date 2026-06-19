import XCTest
@testable import PumpSync

final class DashboardViewTests: XCTestCase {
  func testDashboardMessagesShowProductionReadinessPrompts() {
    let messages = DashboardView.dashboardMessages(
      isBackendConnected: false,
      hasValidatedCredentials: false,
      hasAnyHealthWritePermission: false
    )

    XCTAssertEqual(messages, [])
  }

  func testDashboardMessagesPromptForValidatedCredentialsAfterSignIn() {
    let messages = DashboardView.dashboardMessages(
      isBackendConnected: true,
      hasValidatedCredentials: false,
      hasAnyHealthWritePermission: false
    )

    XCTAssertEqual(messages, ["Validate your pump account in Settings before syncing."])
  }

  func testDashboardMessagesPromptForHealthWriteAccessAfterCredentialsAreValidated() {
    let messages = DashboardView.dashboardMessages(
      isBackendConnected: true,
      hasValidatedCredentials: true,
      hasAnyHealthWritePermission: false
    )

    XCTAssertEqual(messages, ["Enable at least one Apple Health write permission before syncing."])
  }

  func testDashboardMessagesHideDeveloperErrorsWhenReady() {
    let messages = DashboardView.dashboardMessages(
      isBackendConnected: true,
      hasValidatedCredentials: true,
      hasAnyHealthWritePermission: true
    )

    XCTAssertEqual(messages, [])
  }
}
