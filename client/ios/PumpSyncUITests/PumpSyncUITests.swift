import XCTest

final class PumpSyncUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testAppLaunches() {
    let app = XCUIApplication()
    app.launch()
    let hasTabBar = app.tabBars.firstMatch.waitForExistence(timeout: 5)
    let hasSplitSidebar = app.staticTexts["PumpSync"].waitForExistence(timeout: 2)
    XCTAssertTrue(hasTabBar || hasSplitSidebar)
  }

  func testCoreScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture()

    XCTAssertTrue(app.staticTexts["PumpSync"].waitForExistence(timeout: 5))
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Sync"].waitForExistence(timeout: 5))

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))

    tapNavigationLink("Tandem Account", in: app)
    XCTAssertTrue(app.staticTexts["Tandem Source"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()

    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.firstMatch.tap()

    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
  }

  func testIPadAppStoreScreenshots() {
    let app = launchScreenshotFixture()

    attachScreenshot(named: "ipad-pro-13-app-store-listing-01-status-overview.png", from: app)

    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Sync"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-02-sync-workflow.png", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    tapSegment("PumpSync", in: app)
    attachScreenshot(named: "ipad-pro-13-app-store-listing-03-settings-pumpsync-hosted.png", from: app)

    tapSegment("Self-hosted", in: app)
    XCTAssertTrue(app.textFields["https://example.com/api"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-04-settings-self-hosted-connection.png", from: app)

    tapSegment("PumpSync", in: app)
    app.buttons["Subscribe"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["PumpSync Hosted"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-05-hosted-subscription-benefits.png", from: app)
  }

  func testIPadSpecificScreenshots() {
    let app = launchScreenshotFixture()

    XCTAssertTrue(app.staticTexts["PumpSync"].waitForExistence(timeout: 5))
    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-ipad-specific-01-health-detail-sidebar.png", from: app)

    app.navigationBars.buttons.firstMatch.tap()
    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-ipad-specific-02-data-handling-detail-sidebar.png", from: app)

    app.navigationBars.buttons.firstMatch.tap()
    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-ipad-specific-03-developer-detail-sidebar.png", from: app)
  }

  private func launchScreenshotFixture(orientation: UIDeviceOrientation = .portrait) -> XCUIApplication {
    XCUIDevice.shared.orientation = orientation

    let app = XCUIApplication()
    app.launchArguments = ["--pumpsync-screenshot-mode"]
    app.launchEnvironment["PUMPSYNC_SCREENSHOT_MODE"] = "1"
    app.launch()
    return app
  }

  private func navigate(to title: String, in app: XCUIApplication) {
    if app.tabBars.buttons[title].waitForExistence(timeout: 2) {
      app.tabBars.buttons[title].tap()
      return
    }

    let button = app.buttons[title]
    if button.waitForExistence(timeout: 2) {
      button.tap()
      return
    }

    let cell = app.cells.containing(.staticText, identifier: title).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Could not find navigation item \(title)")
    cell.tap()
  }

  private func tapNavigationLink(_ title: String, in app: XCUIApplication) {
    let identifier = [
      "Tandem Account": "TandemAccountLink",
      "Apple Health": "AppleHealthLink",
      "Data Handling": "DataHandlingLink",
      "Developer": "DeveloperLink"
    ][title]

    if let identifier {
      let identifiedLink = app.buttons[identifier]
      if identifiedLink.waitForExistence(timeout: 2) {
        identifiedLink.tap()
        return
      }
    }

    let link = app.buttons[title]
    if link.waitForExistence(timeout: 2) {
      link.tap()
      return
    }

    let cell = app.cells.containing(.staticText, identifier: title).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Could not find navigation link \(title)")
    cell.tap()
  }

  private func tapSegment(_ title: String, in app: XCUIApplication) {
    let segment = app.segmentedControls.buttons[title]
    if segment.waitForExistence(timeout: 2) {
      segment.tap()
      return
    }

    let button = app.buttons[title]
    XCTAssertTrue(button.waitForExistence(timeout: 5), "Could not find segment \(title)")
    button.tap()
  }

  private func attachScreenshot(named name: String, from app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
