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

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))
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
    assertDeveloperDiagnosticsVisible(in: app)
  }

  func testDeveloperDiagnosticsActionsUseUniqueAccessibleNames() {
    let app = launchScreenshotFixture()

    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)

    assertDeveloperDiagnosticsVisible(in: app)
  }

  func testAccessibilityDynamicTypeScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture(
      launchEnvironment: [
        "UIPreferredContentSizeCategoryName": "UICTContentSizeCategoryAccessibilityXXXL"
      ]
    )

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))

    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Sync"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Sync Now"].waitForExistence(timeout: 5))

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Subscribe"].waitForExistence(timeout: 5))

    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.buttons["Share Support Bundle"].waitForExistence(timeout: 5))
  }

  func testDarkModeCoreScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture(launchArguments: ["-AppleInterfaceStyle", "Dark"])

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
  }

  func testIPadAppStoreScreenshots() {
    let app = launchScreenshotFixture()

    attachScreenshot(named: "ipad-pro-13-app-store-listing-01-sync-overview.png", from: app)

    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Sync"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-02-sync-workflow.png", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    tapSegment("PumpSync", in: app)
    attachScreenshot(named: "ipad-pro-13-app-store-listing-03-settings-pumpsync-hosted.png", from: app)

    tapSegment("Self-hosted", in: app)
    assertSelfHostedServerURLField(in: app)
    attachScreenshot(named: "ipad-pro-13-app-store-listing-05-settings-self-hosted-connection.png", from: app)

    tapSegment("PumpSync", in: app)

    tapNavigationLink("Tandem Account", in: app)
    XCTAssertTrue(app.staticTexts["Tandem Source"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-06-tandem-account.png", from: app)
    app.navigationBars.buttons.firstMatch.tap()

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-07-apple-health.png", from: app)

    app.navigationBars.buttons.firstMatch.tap()
    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-08-data-handling.png", from: app)

    app.navigationBars.buttons.firstMatch.tap()
    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-09-developer.png", from: app)

    app.navigationBars.buttons.firstMatch.tap()
    tapSegment("PumpSync", in: app)
    app.buttons["Subscribe"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["PumpSync Hosted"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-04-hosted-subscription-benefits.png", from: app)
  }

  func testIPhoneAppStoreScreenshots() {
    let app = launchScreenshotFixture()

    attachScreenshot(named: "iphone-6-7-app-store-listing-01-sync-overview.png", from: app)

    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Sync"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-02-sync-workflow.png", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    tapSegment("PumpSync", in: app)
    attachScreenshot(named: "iphone-6-7-app-store-listing-03-settings-pumpsync-hosted.png", from: app)

    tapSegment("Self-hosted", in: app)
    assertSelfHostedServerURLField(in: app)
    attachScreenshot(named: "iphone-6-7-app-store-listing-05-settings-self-hosted-connection.png", from: app)

    tapSegment("PumpSync", in: app)

    tapNavigationLink("Tandem Account", in: app)
    XCTAssertTrue(app.staticTexts["Tandem Source"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-06-tandem-account.png", from: app)
    app.navigationBars.buttons.firstMatch.tap()

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-07-apple-health.png", from: app)
    app.navigationBars.buttons.firstMatch.tap()

    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-08-data-handling.png", from: app)
    app.navigationBars.buttons.firstMatch.tap()

    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-09-developer.png", from: app)

    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["Subscribe"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["PumpSync Hosted"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-04-hosted-subscription-benefits.png", from: app)
  }

  private func launchScreenshotFixture(
    orientation: UIDeviceOrientation = .portrait,
    launchArguments: [String] = [],
    launchEnvironment: [String: String] = [:]
  ) -> XCUIApplication {
    XCUIDevice.shared.orientation = orientation

    let app = XCUIApplication()
    app.launchArguments = ["--pumpsync-screenshot-mode"] + launchArguments
    app.launchEnvironment["PUMPSYNC_SCREENSHOT_MODE"] = "1"
    for (key, value) in launchEnvironment {
      app.launchEnvironment[key] = value
    }
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

  private func assertDeveloperDiagnosticsVisible(in app: XCUIApplication) {
    XCTAssertTrue(app.staticTexts["App Event Log"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["iOS Performance Diagnostics"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Copy App Event Log"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Clear App Event Log"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Copy iOS Performance Diagnostics"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Clear iOS Performance Diagnostics"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Share Support Bundle"].waitForExistence(timeout: 5))
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

  private func assertSelfHostedServerURLField(in app: XCUIApplication) {
    let field = app.textFields["Server URL"]

    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(field.placeholderValue, "Server URL")
    XCTAssertFalse(app.staticTexts["Server URL"].exists)
  }

  private func attachScreenshot(named name: String, from app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
