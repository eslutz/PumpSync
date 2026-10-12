import XCTest
import UIKit

@MainActor
final class PumpSyncUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testPreviewEntryPointsLiveOnlyInDiagnostics() {
    let app = launchScreenshotFixture()
    XCTAssertFalse(app.buttons["Preview Import"].exists)
    navigate(to: "Settings", in: app)
    XCTAssertFalse(app.buttons["Sample Preview"].exists)
    tapNavigationLink("Developer", in: app)
    let inspect = app.buttons["Inspect source data"]
    if !inspect.isHittable { app.swipeUp() }
    XCTAssertTrue(inspect.waitForExistence(timeout: 5))
    inspect.tap()
    XCTAssertTrue(app.staticTexts["PreviewSafetyNotice"].waitForExistence(timeout: 5))
  }

  func testConnectionRecoveryOpensSettingsTab() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapSegment("Self-hosted", in: app)
    navigate(to: "Sync", in: app)
    let settings = app.buttons["Connection Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    attachScreenshot(named: "connection-recovery-card", from: app)
    settings.tap()
    XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
  }



  func testAppLaunches() {
    let app = XCUIApplication()
    app.launch()
    let hasTabBar = app.tabBars.firstMatch.waitForExistence(timeout: 5)
    let hasSplitSidebar = app.staticTexts["PumpSync"].waitForExistence(timeout: 2)
    XCTAssertTrue(hasTabBar || hasSplitSidebar)
  }

  func testSyncHelpLivesInSettingsAboutScreen() {
    let app = launchScreenshotFixture(launchArguments: [])
    XCTAssertFalse(app.staticTexts["How Syncing Runs"].exists)
    navigate(to: "Settings", in: app)
    let about = app.buttons["AboutPumpSyncLink"]
    for _ in 0..<10 {
      if about.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(about.waitForExistence(timeout: 5))
    XCTAssertTrue(about.isHittable)
    about.tap()
    XCTAssertTrue(app.staticTexts["Insulin and carbohydrates"].waitForExistence(timeout: 5))
    attachScreenshot(named: "about-quick-guide", from: app)
    let whileSyncing = app.staticTexts["While syncing"]
    for _ in 0..<10 {
      if whileSyncing.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(whileSyncing.isHittable)
    attachScreenshot(named: "about-quick-guide-lower", from: app)
    let completion = app.staticTexts["Last Successful Sync shows the last completed sync, even if there were no new records."]
    for _ in 0..<10 {
      if completion.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(completion.isHittable)
    attachScreenshot(named: "about-quick-guide-completion", from: app)
  }

  func testPreviewSyncFixtureShowsDisabledSyncAction() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-syncing"])

    let syncingButton = app.buttons["Syncing"]
    XCTAssertTrue(syncingButton.waitForExistence(timeout: 5))
    XCTAssertFalse(syncingButton.isEnabled)
  }

  func testRunningBannerDismissalPreservesSyncButtonAndTabNavigation() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-syncing"])
    XCTAssertTrue(app.staticTexts["Starting secure service…"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["View"].exists)
    app.buttons["Dismiss notification"].tap()
    XCTAssertTrue(app.staticTexts["Starting secure service…"].waitForNonExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Syncing"].exists)
    XCTAssertFalse(app.buttons["Syncing"].isEnabled)
    navigate(to: "Settings", in: app)
    navigate(to: "Sync", in: app)
    XCTAssertFalse(app.staticTexts["Starting secure service…"].exists)
    XCTAssertTrue(app.buttons["Syncing"].exists)
    XCTAssertFalse(app.buttons["Syncing"].isEnabled)
  }

  func testRunningSyncBannerRemainsVisibleAfterSwitchingToSettings() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-syncing"])

    XCTAssertTrue(app.staticTexts["Starting secure service…"].waitForExistence(timeout: 5))

    navigate(to: "Settings", in: app)

    XCTAssertTrue(app.staticTexts["Starting secure service…"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
  }

  func testSuccessfulSyncBannerDismissesAfterEightSeconds() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-sync-success"])
    let banner = app.staticTexts["Sync complete"]

    XCTAssertTrue(banner.waitForExistence(timeout: 5))
    let disappeared = banner.waitForNonExistence(timeout: 10)
    if !disappeared { recordUIState(named: "success-banner-did-not-dismiss", in: app) }
    XCTAssertTrue(disappeared)
  }

  func testActionableFailureBannerDoesNotAutoDismiss() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-sync-failure"])
    let banner = app.staticTexts["Sync needs attention"]

    XCTAssertTrue(banner.waitForExistence(timeout: 5))
    recordUIState(named: "actionable-failure-banner", in: app)
    XCTAssertTrue(app.buttons["Try Again"].exists)
    XCTAssertFalse(banner.waitForNonExistence(timeout: 9))
  }

  func testMinimumHitTargetAcceptsOnlyFloatingPointPrecisionError() {
    XCTAssertTrue(meetsMinimumHitTargetDimension(CGFloat(44).nextDown))
    XCTAssertTrue(meetsMinimumHitTargetDimension(43.999999999999986))
    XCTAssertTrue(meetsMinimumHitTargetDimension(44))
    XCTAssertFalse(meetsMinimumHitTargetDimension(43.999))
  }

  private func meetsMinimumHitTargetDimension(_ dimension: CGFloat) -> Bool {
    // Accessibility frames can lose a few floating-point bits when their
    // coordinates are converted. Keep the 44-point requirement while
    // tolerating only numerical noise, not a visibly smaller hit target.
    dimension >= 44 - 1e-9
  }

  func testFailureBannerKeepsNavigationAndActionsReachable() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-sync-failure"])
    XCTAssertTrue(app.staticTexts["Sync needs attention"].waitForExistence(timeout: 5))
    recordUIState(named: "failure-banner-navigation", in: app)
    // Leave readable text width rather than squeezing the headline and
    // recovery action into single-character columns at accessibility sizes.
    if UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory {
      XCTAssertGreaterThan(app.staticTexts["Sync needs attention"].frame.width, app.windows.firstMatch.frame.width / 2)
    } else {
      let content = app.staticTexts["Sync needs attention"].frame
        .union(app.staticTexts["Sync could not be completed. Try again."].frame)
        .union(app.buttons["Try Again"].frame)
        .union(app.buttons["Dismiss notification"].frame)
      XCTAssertLessThanOrEqual(
        app.otherElements["Sync needs attention"].firstMatch.frame.height,
        content.height + 40,
        "A compact notification must not reserve empty space over the app content"
      )
    }

    let settings = app.tabBars.buttons["Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 2))
    XCTAssertTrue(app.windows.firstMatch.frame.contains(settings.frame), "Banner pushed Settings outside the viewport")
    XCTAssertTrue(settings.isHittable)
    let dismiss = app.buttons["Dismiss notification"]
    XCTAssertTrue(dismiss.isHittable)
    XCTAssertTrue(meetsMinimumHitTargetDimension(dismiss.frame.width), "Dismiss width must be at least 44 points: \(dismiss.frame.width)")
    XCTAssertTrue(meetsMinimumHitTargetDimension(dismiss.frame.height), "Dismiss height must be at least 44 points: \(dismiss.frame.height)")

    // The full message and recovery action remain available by scrolling the
    // bounded banner at large text sizes, without scrolling the app content.
    let retry = app.buttons["Try Again"]
    for _ in 0..<5 {
      if retry.isHittable { break }
      app.scrollViews["SyncStatusBannerContent"].swipeUp()
    }
    XCTAssertTrue(retry.isHittable)
    XCTAssertGreaterThan(retry.frame.width, 44)
    recordUIState(named: "failure-banner-recovery-action", in: app)
    settings.tap()
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Sync needs attention"].exists)
    dismiss.tap()
    XCTAssertTrue(app.staticTexts["Sync needs attention"].waitForNonExistence(timeout: 3))
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.buttons["Sync Now"].waitForExistence(timeout: 5))
  }

  func testCoreScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture()

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Successful Sync"].waitForExistence(timeout: 5))

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

  func testInstallationIDCopiesFromContextMenu() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)

    let row = app.descendants(matching: .any)["InstallationIDRow"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let installationID = row.value as? String
    XCTAssertNotNil(installationID)
    XCTAssertFalse(app.buttons["Copy Installation ID"].exists)
    attachScreenshot(named: "installation-id-without-separate-copy-row", from: app)

    row.press(forDuration: 1)
    let copy = app.buttons["Copy"].firstMatch
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    attachScreenshot(named: "installation-id-copy-menu", from: app)
    copy.tap()
    XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
    XCTAssertEqual(row.value as? String, installationID)
    let expectedCopy = XCTAttachment(string: installationID ?? "")
    expectedCopy.name = "expected-copied-installation-id"
    expectedCopy.lifetime = .keepAlways
    add(expectedCopy)
  }

  func testDeveloperDiagnosticsActionsUseUniqueAccessibleNames() {
    let app = launchScreenshotFixture()

    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)

    assertDeveloperDiagnosticsVisible(in: app)
  }

  func testSettingsShowsCompactInsulinConcentrationRow() {
    let app = launchScreenshotFixture()

    navigate(to: "Settings", in: app)

    XCTAssertTrue(app.staticTexts["Insulin Concentration"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Apple Health records 1x pump units"].exists)
  }

  func testAccessibilityDynamicTypeScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture(
      launchEnvironment: [
        "UIPreferredContentSizeCategoryName": "UICTContentSizeCategoryAccessibilityXXXL"
      ]
    )

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))

    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Successful Sync"].waitForExistence(timeout: 5))
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
    let initialApp = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    XCTAssertTrue(initialApp.buttons["Sync Past 14 Days"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-01-status-overview.png", from: initialApp)
    initialApp.terminate()

    let app = launchScreenshotFixture()
    XCTAssertTrue(app.staticTexts["Last Successful Sync"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-02-sync-workflow.png", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    tapSegment("PumpSync", in: app)
    attachScreenshot(named: "ipad-pro-13-app-store-listing-03-settings-pumpsync.png", from: app)

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
    XCTAssertTrue(app.staticTexts["PumpSync Subscription"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-04-subscription-benefits.png", from: app)
  }

  func testIPhoneAppStoreScreenshots() {
    let initialApp = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    XCTAssertTrue(initialApp.buttons["Sync Past 14 Days"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-01-status-overview.png", from: initialApp)
    initialApp.terminate()

    let app = launchScreenshotFixture()
    XCTAssertTrue(app.staticTexts["Last Successful Sync"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-02-sync-workflow.png", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    tapSegment("PumpSync", in: app)
    attachScreenshot(named: "iphone-6-7-app-store-listing-03-settings-pumpsync.png", from: app)

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

    tapNavigationLink("Insulin Concentration", in: app)
    XCTAssertTrue(app.staticTexts["Current Setting"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-insulin-concentration-alignment.png", from: app)
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
    XCTAssertTrue(app.staticTexts["PumpSync Subscription"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-04-subscription-benefits.png", from: app)
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

    let button = app.buttons[title].firstMatch
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
    XCTAssertTrue(app.staticTexts["Device Performance Diagnostics"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Copy App Event Log"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Clear App Event Log"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Copy Device Performance Diagnostics"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Clear Device Performance Diagnostics"].waitForExistence(timeout: 5))
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

  private func recordUIState(named name: String, in app: XCUIApplication) {
    attachScreenshot(named: name, from: app)
    let attachment = XCTAttachment(string: app.debugDescription)
    attachment.name = name + "-hierarchy"
    attachment.lifetime = .keepAlways
    add(attachment)
    print("UISTATE \(name)\n\(app.debugDescription)")
  }
}
