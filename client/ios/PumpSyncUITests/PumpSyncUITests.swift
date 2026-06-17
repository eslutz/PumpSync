import XCTest

final class PumpSyncUITests: XCTestCase {
  func testAppLaunches() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
  }
}
