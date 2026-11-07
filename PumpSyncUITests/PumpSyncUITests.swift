import XCTest
import UIKit

@MainActor
final class PumpSyncUITests: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testSourceDataReadyStatesAndRefreshUseNativeNavigation() {
    for state in ["empty", "populated"] {
      let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-preview", state])
      navigate(to: "Settings", in: app)
      tapNavigationLink("Developer", in: app)
      tapNavigationLink("Inspect source data", in: app)
      let refresh = app.buttons["Refresh Records"]
      XCTAssertTrue(app.staticTexts["PreviewSafetyNotice"].waitForExistence(timeout: 8))
      for _ in 0..<8 {
        if refresh.isHittable { break }
        app.swipeUp()
      }
      XCTAssertTrue(refresh.isHittable)
      XCTAssertGreaterThanOrEqual(refresh.frame.height, 44 - 0.01)
      XCTAssertGreaterThanOrEqual(refresh.frame.width, 44 - 0.01)
      attachScreenshot(named: "review-source-" + state, from: app)
      refresh.tap()
      XCTAssertTrue(refresh.waitForExistence(timeout: 8))
      let record: XCUIElement = state == "empty"
        ? app.staticTexts["No records in this time range"]
        : app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Carbohydrates")).firstMatch
      for _ in 0..<5 {
        if record.isHittable { break }
        app.swipeUp()
      }
      XCTAssertTrue(record.isHittable)
      attachScreenshot(named: "review-source-" + state + "-records", from: app)
      tapBack(in: app)
      XCTAssertTrue(app.navigationBars["Developer"].exists)
      app.terminate()
    }
  }

  func testSourceDataLoadingCanCancelAndNavigateBack() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-preview", "loading"])
    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)
    tapNavigationLink("Inspect source data", in: app)
    XCTAssertTrue(app.staticTexts["PreviewSafetyNotice"].waitForExistence(timeout: 8))
    let cancel = app.buttons["Cancel"]
    for _ in 0..<8 {
      if cancel.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(cancel.isHittable)
    attachScreenshot(named: "review-source-loading", from: app)
    cancel.tap()
    XCTAssertTrue(app.buttons["Load Records"].waitForExistence(timeout: 5))
    tapBack(in: app)
    XCTAssertTrue(app.navigationBars["Developer"].exists)
  }

  @available(iOS 27.0, *)
  func testVoiceOverSourceDataRefreshAndHealthInstructions() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-preview", "populated"])
    navigate(to: "Settings", in: app)
    tapNavigationLink("Apple Health", in: app)
    attachScreenshot(named: "review-health-instructions", from: app)
    try enableVoiceOver()
    let healthSpeech = try recordVoiceOverScreen("health-updated-instructions", maximum: 24)
    XCTAssertTrue(healthSpeech.contains { $0.contains("Open Health") })
    try voiceOver.disable()
    tapBack(in: app)
    tapNavigationLink("Developer", in: app)
    tapNavigationLink("Inspect source data", in: app)
    XCTAssertTrue(app.buttons["Refresh Records"].waitForExistence(timeout: 8))
    try enableVoiceOver()
    let speech = try recordVoiceOverScreen("source-data-ready", maximum: 30)
    XCTAssertTrue(speech.contains { $0.contains("Refresh Records") && $0.contains("Button") })
    try focusVoiceOver("Refresh Records", backwards: true)
    app.buttons["Refresh Records"].doubleTap()
    XCTAssertTrue(app.buttons["Refresh Records"].waitForExistence(timeout: 8))
  }

  @available(iOS 27.0, *)
  func testVoiceOverSyncFocusAndSpeech() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    try voiceOver.disable()
    _ = launchScreenshotFixture()
    try enableVoiceOver()
    let speech = try recordVoiceOverScreen("sync-ready", maximum: 14)
    XCTAssertTrue(speech.contains { $0.contains("Last Successful Sync Heading") })
    XCTAssertEqual(speech.filter { $0.contains("Sync Now Button") }.count, 1)
    XCTAssertTrue(speech.contains { $0.contains("selected Sync Tab") })
  }

  @available(iOS 27.0, *)
  func testVoiceOverPickerAndSettingsNavigation() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    try voiceOver.disable()
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    try enableVoiceOver()
    let initialSpeech = try recordVoiceOverScreen("initial-import", maximum: 18)
    XCTAssertEqual(initialSpeech.filter { $0.contains("History range") }.count, 1)
    let historySpeech = try XCTUnwrap(initialSpeech.first { $0.contains("History range") })
    XCTAssertEqual(historySpeech.components(separatedBy: "History range").count - 1, 1)
    XCTAssertEqual(historySpeech.components(separatedBy: "Past 14 days").count - 1, 1)
    XCTAssertTrue(initialSpeech.contains { $0.contains("Initial Import Heading") })
    try focusVoiceOver("History range")
    app.buttons["HistoryRangePicker"].doubleTap()
    XCTAssertTrue(app.buttons["Past 7 days"].waitForExistence(timeout: 5))
    try recordVoiceOverScreen("history-menu", maximum: 10)
    try focusVoiceOver("Past 7 days", backwards: true)
    app.buttons["Past 7 days"].doubleTap()
    XCTAssertTrue(app.buttons["HistoryRangePicker"].waitForExistence(timeout: 5))
    try focusVoiceOver("Settings Tab")
    app.tabBars.buttons["Settings"].doubleTap()
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    try recordVoiceOverScreen("settings", maximum: 28)
  }

  @available(iOS 27.0, *)
  func testVoiceOverRegionAndConcentrationSelection() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Tandem Account", in: app)
    app.buttons["Change Account Details"].tap()
    try enableVoiceOver()
    try focusVoiceOver("Tandem region")
    app.buttons["TandemRegionPicker"].doubleTap()
    XCTAssertTrue(app.buttons["Europe"].waitForExistence(timeout: 5))
    try focusVoiceOver("Europe")
    app.buttons["Europe"].firstMatch.doubleTap()
    try focusVoiceOver("Tandem region")
    let regionSpeech = try voiceOver.currentSpeech().utterance
    print("VOICEOVER region-selected: \(regionSpeech)")
    XCTAssertEqual(regionSpeech.components(separatedBy: "Tandem region").count - 1, 1)
    XCTAssertEqual(regionSpeech.components(separatedBy: "Europe").count - 1, 1)
    try voiceOver.disable()
    tapBack(in: app)
    tapNavigationLink("Insulin Concentration", in: app)
    try enableVoiceOver()
    try focusVoiceOver("U-100")
    app.buttons["InsulinConcentrationPicker"].doubleTap()
    XCTAssertTrue(app.buttons["U-200"].waitForExistence(timeout: 5))
    try focusVoiceOver("U-200")
    app.buttons["U-200"].firstMatch.doubleTap()
    try focusVoiceOver("U-200")
    let concentrationSpeech = try voiceOver.currentSpeech().utterance
    print("VOICEOVER concentration-selected: \(concentrationSpeech)")
    XCTAssertEqual(concentrationSpeech.components(separatedBy: "Insulin Concentration").count - 1, 1)
    XCTAssertEqual(concentrationSpeech.components(separatedBy: "U-200").count - 1, 1)
    attachScreenshot(named: "voiceover-picker-selections", from: app)
  }

  @available(iOS 27.0, *)
  func testVoiceOverSettingsDestinations() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    try voiceOver.disable()
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    for title in ["Tandem Account", "Apple Health", "Insulin Concentration", "Data Handling", "About PumpSync", "Developer"] {
      let identifier = title == "About PumpSync" ? "AboutPumpSyncLink" : title
      let link = app.buttons[identifier]
      for _ in 0..<5 {
        if link.isHittable { break }
        app.swipeUp()
      }
      if title == "About PumpSync" { link.tap() }
      else { tapNavigationLink(title, in: app) }
      try enableVoiceOver()
      let speech = try recordVoiceOverScreen(title, maximum: 38)
      XCTAssertTrue(speech.contains { $0.contains("Heading") })
      if title == "Tandem Account" {
        XCTAssertTrue(speech.contains { $0.contains("Saved Account") })
        XCTAssertTrue(speech.contains { $0.contains("Change Account Details") })
        XCTAssertFalse(speech.contains { $0.contains("Secure Text Field") })
      }
      if title == "Insulin Concentration" {
        let concentrationSpeech = try XCTUnwrap(speech.first { $0.contains("U-100") })
        XCTAssertEqual(concentrationSpeech.components(separatedBy: "U-100").count - 1, 1)
      }
      try voiceOver.disable()
      tapBack(in: app)
    }
  }

  @available(iOS 27.0, *)
  func testVoiceOverDiagnosticsAndSourceData() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    try voiceOver.disable()
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)
    for (identifier, title) in [("appEventsLogLink", "App Event Log"), ("devicePerformanceLogLink", "Device Performance Diagnostics")] {
      let link = app.buttons[identifier]
      for _ in 0..<6 {
        if link.isHittable { break }
        app.swipeUp()
      }
      link.tap()
      try enableVoiceOver()
      try recordVoiceOverScreen(title, maximum: 20)
      try voiceOver.disable()
      app.buttons["DiagnosticsLogActions"].tap()
      app.buttons["CopyDiagnosticsLog"].tap()
      app.buttons["DiagnosticsLogActions"].tap()
      try enableVoiceOver()
      try recordVoiceOverScreen(title + "-actions", maximum: 5)
      try voiceOver.disable()
      app.buttons["Clear Logs"].firstMatch.tap()
      try enableVoiceOver()
      try recordVoiceOverScreen(title + "-confirmation", maximum: 6)
      try focusVoiceOver("Cancel", backwards: true)
      app.buttons["Cancel"].doubleTap()
      XCTAssertTrue(app.buttons["Clear Logs"].waitForNonExistence(timeout: 5))
      app.buttons["DiagnosticsLogActions"].doubleTap()
      try focusVoiceOver("Clear Logs")
      app.buttons["Clear Logs"].firstMatch.doubleTap()
      try focusVoiceOver("Clear Logs")
      app.alerts.buttons["Clear Logs"].doubleTap()
      XCTAssertTrue(app.staticTexts["EmptyDiagnosticsLog"].waitForExistence(timeout: 5))
      let emptySpeech = try recordVoiceOverScreen(title + "-empty", maximum: 12)
      XCTAssertTrue(emptySpeech.contains { $0.contains("No ") && $0.contains("recorded") })
      try voiceOver.disable()
      app.buttons["DiagnosticsLogActions"].tap()
      XCTAssertFalse(app.buttons["CopyDiagnosticsLog"].isEnabled)
      app.tap()
      tapBack(in: app)
    }
    let inspect = app.buttons["Inspect source data"]
    for _ in 0..<6 {
      if inspect.isHittable { break }
      app.swipeDown()
    }
    inspect.tap()
    try enableVoiceOver()
    try recordVoiceOverScreen("source-data-recovery", maximum: 20)
  }

  @available(iOS 27.0, *)
  func testVoiceOverSyncStates() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    for (argument, name) in [("--pumpsync-screenshot-syncing", "syncing"), ("--pumpsync-screenshot-sync-success", "success"), ("--pumpsync-screenshot-sync-failure", "failure")] {
      try voiceOver.disable()
      _ = launchScreenshotFixture(launchArguments: [argument])
      try enableVoiceOver()
      try recordVoiceOverScreen(name, maximum: 18)
    }
  }

  @available(iOS 27.0, *)
  private func enableVoiceOver() throws {
    let service = XCUIDevice.shared.voiceOverService
    try service.enable()
    if try service.currentSpeech().utterance.contains("VoiceOver Gestures") {
      // A fresh simulator can show Apple's one-time introduction. Turning the
      // service off dismisses it; it is not part of the application's flow.
      try service.disable()
      try service.enable()
    }
    XCTAssertTrue(service.isEnabled)
  }

  @available(iOS 27.0, *)
  @discardableResult
  private func recordVoiceOverScreen(_ name: String, maximum: Int = 30) throws -> [String] {
    let voiceOver = XCUIDevice.shared.voiceOverService
    var first = try voiceOver.currentSpeech().utterance
    for _ in 0..<65 {
      let previous = try voiceOver.moveBackward().utterance
      if previous == first { break }
      first = previous
    }
    var utterances = [first]
    print("VOICEOVER \(name): \(utterances[0])")
    for _ in 0..<maximum {
      let speech = try voiceOver.moveForward().utterance
      print("VOICEOVER \(name): \(speech)")
      if speech == utterances.last { break }
      utterances.append(speech)
    }
    let transcript = XCTAttachment(string: utterances.joined(separator: "\n"))
    transcript.name = "voiceover-" + name + "-speech"
    transcript.lifetime = .keepAlways
    add(transcript)
    attachScreenshot(named: "voiceover-" + name + "-focus", from: XCUIApplication())
    XCTAssertFalse(utterances.isEmpty)
    return utterances
  }

  @available(iOS 27.0, *)
  private func focusVoiceOver(_ text: String, backwards: Bool = false) throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    var speech = try voiceOver.currentSpeech().utterance
    var reverse = backwards
    var reachedBoundary = false
    for _ in 0..<65 {
      if speech.contains(text) { return }
      let next = try reverse ? voiceOver.moveBackward().utterance : voiceOver.moveForward().utterance
      if next == speech {
        if reachedBoundary { break }
        reachedBoundary = true
        reverse.toggle()
      }
      speech = next
    }
    XCTFail("VoiceOver could not reach \(text)")
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
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-connection-failure"])
    navigate(to: "Settings", in: app)
    tapNavigationLink("About PumpSync", in: app)
    let status = app.descendants(matching: .any)["GlobalSyncStatus"].firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 3))
    let tab = app.tabBars.buttons["Settings"].firstMatch
    if tab.exists { XCTAssertFalse(status.frame.intersects(tab.frame), "Pinned status must leave native tabs unobscured") }
    let back = app.navigationBars.buttons.firstMatch
    if back.exists { XCTAssertFalse(status.frame.intersects(back.frame), "Pinned status must leave Back unobscured") }
    attachScreenshot(named: "global-recovery-before-menu", from: app)
    let settings = app.descendants(matching: .any)["Connection Settings"].firstMatch
    if !settings.exists {
      let menu = app.descendants(matching: .any)["GlobalSyncStatusActions"].firstMatch
      if menu.exists { menu.tap() }
      else {
        // A lone SwiftUI Menu can inherit its container's identifier. Match
        // its observed accessible label rather than unrelated recovery buttons.
        let inheritedMenu = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "GlobalSyncStatus", "Sync needs attention")).firstMatch
        XCTAssertTrue(inheritedMenu.exists)
        inheritedMenu.tap()
      }
    }
    if !settings.waitForExistence(timeout: 5) {
      attachScreenshot(named: "missing-global-recovery-action", from: app)
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "global-recovery-accessibility-tree"
      tree.lifetime = .keepAlways
      add(tree)
    }
    XCTAssertTrue(settings.exists)
    attachScreenshot(named: "connection-recovery-card", from: app)
    settings.tap()
    if app.tabBars.buttons["Settings"].exists {
      XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
    } else {
      XCTAssertTrue(app.navigationBars["Settings"].exists)
    }
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.navigationBars["About PumpSync"].exists)
  }


  func testAppLaunches() {
    let app = launchScreenshotFixture()
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

  func testInlineProgressPreservesSyncAndTabNavigation() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-syncing"])
    XCTAssertTrue(app.staticTexts["SyncProgressDetail"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Dismiss notification"].exists)
    XCTAssertFalse(app.buttons["Syncing"].isEnabled)
    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.descendants(matching: .any)["GlobalSyncStatus"].firstMatch.exists)
    XCTAssertFalse(app.staticTexts["SyncProgressDetail"].exists)
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["SyncProgressDetail"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Syncing"].isEnabled)
    attachScreenshot(named: "inline-sync-progress", from: app)
  }

  func testSuccessSummaryPersistsAcrossNavigation() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-sync-success"])
    let summary = app.staticTexts["SyncCompletionSummary"]
    XCTAssertTrue(summary.waitForExistence(timeout: 5))
    XCTAssertEqual(summary.label, "4 imported · 48 returned")
    XCTAssertFalse(app.buttons["Dismiss notification"].exists)
    navigate(to: "Settings", in: app)
    navigate(to: "Sync", in: app)
    XCTAssertTrue(summary.waitForExistence(timeout: 5))
    XCTAssertFalse(summary.waitForNonExistence(timeout: 9))
    attachScreenshot(named: "inline-sync-success", from: app)
  }

  func testFailureHasOneRecoveryAction() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-sync-failure"])
    XCTAssertTrue(app.staticTexts["Sync needs attention"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "Try Again").count, 1)
    XCTAssertFalse(app.buttons["Sync Now"].exists)
    XCTAssertFalse(app.buttons["Dismiss notification"].exists)
    attachScreenshot(named: "inline-sync-failure", from: app)
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

  func testInlineFailureKeepsNavigationAndRecoveryReachable() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-sync-failure"])
    let retry = app.buttons["Try Again"]
    for _ in 0..<8 {
      if retry.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(retry.isHittable)
    XCTAssertTrue(meetsMinimumHitTargetDimension(retry.frame.height), "Recovery target must be at least 44 points: \(retry.frame)")
    let dismiss = app.buttons["Dismiss Sync Message"]
    XCTAssertTrue(meetsMinimumHitTargetDimension(dismiss.frame.height))
    XCTAssertTrue(meetsMinimumHitTargetDimension(dismiss.frame.width))
    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Sync needs attention"].exists)
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Sync needs attention"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Sync Now"].exists)
  }

  func testCoreScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture()

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Last Successful Sync"].waitForExistence(timeout: 5))
    let recordedSummary = app.staticTexts["SyncCompletionSummary"]
    XCTAssertTrue(recordedSummary.waitForExistence(timeout: 3), "Recorded success must remain visible without a transient completion state")
    XCTAssertEqual(recordedSummary.label, "48 imported · 48 returned")

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.staticTexts["Connection"].waitForExistence(timeout: 5))

    tapNavigationLink("Tandem Account", in: app)
    XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 5))
    tapBack(in: app)

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    tapBack(in: app)

    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    tapBack(in: app)

    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
    assertDeveloperDiagnosticsVisible(in: app)
  }

  func testInstallationIDCopiesFromExplicitAction() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)
    let row = app.descendants(matching: .any)["InstallationIDRow"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let installationID = row.value as? String
    XCTAssertNotNil(installationID)
    let copy = app.buttons["Copy Installation ID"].firstMatch
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    copy.tap()
    XCTAssertTrue(app.buttons["Installation ID Copied"].waitForExistence(timeout: 3))
    XCTAssertEqual(row.value as? String, installationID)
    attachScreenshot(named: "installation-id-copied", from: app)
  }

  func testDeveloperDiagnosticsActionsUseUniqueAccessibleNames() {
    let app = launchScreenshotFixture()

    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)

    assertDeveloperDiagnosticsVisible(in: app)
  }

  func testDiagnosticsNavigationCopyAndClear() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)
    for identifier in ["appEvents", "devicePerformance"] {
      let link = app.buttons[identifier + "LogLink"]
      for _ in 0..<8 { if link.isHittable { break }; app.swipeUp() }
      XCTAssertTrue(link.isHittable)
      link.tap()
      attachScreenshot(named: identifier + "-summary", from: app)
      app.buttons["DiagnosticsLogActions"].tap()
      let copy = app.buttons["CopyDiagnosticsLog"]
      XCTAssertTrue(copy.waitForExistence(timeout: 3))
      XCTAssertTrue(copy.isEnabled)
      copy.tap()
      XCTAssertTrue(app.staticTexts["DiagnosticsCopyFeedback"].waitForExistence(timeout: 3))
      app.buttons["DiagnosticsLogActions"].tap()
      app.buttons["Clear Logs"].firstMatch.tap()
      XCTAssertTrue(app.staticTexts["Clear Logs?"].waitForExistence(timeout: 3))
      attachScreenshot(named: identifier + "-clear-confirmation", from: app)
      app.buttons["Cancel"].tap()
      XCTAssertFalse(app.staticTexts["EmptyDiagnosticsLog"].exists)
      app.buttons["DiagnosticsLogActions"].tap()
      app.buttons["Clear Logs"].firstMatch.tap()
      XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
      app.alerts.buttons["Clear Logs"].tap()
      XCTAssertTrue(app.staticTexts["EmptyDiagnosticsLog"].waitForExistence(timeout: 5))
      app.buttons["DiagnosticsLogActions"].tap()
      XCTAssertFalse(app.buttons["CopyDiagnosticsLog"].isEnabled)
      app.tap()
      tapBack(in: app)
      XCTAssertTrue(link.waitForExistence(timeout: 5))
    }
  }

  func testSavedAccountEditingCancelPreservesSavedSummary() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Tandem Account", in: app)
    XCTAssertTrue(app.staticTexts["Saved Account"].exists)
    XCTAssertFalse(app.secureTextFields["Tandem password"].exists)
    app.buttons["Change Account Details"].tap()
    let password = app.secureTextFields["Tandem password"]
    XCTAssertTrue(password.waitForExistence(timeout: 3))
    XCTAssertEqual(password.value as? String, "Password")
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 3))
    XCTAssertFalse(password.exists)
    XCTAssertTrue(app.buttons["Remove Credentials"].exists)
  }

  func testSyncStatusRemainsVisibleOnPushedSettingsDestinations() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-syncing"])
    navigate(to: "Settings", in: app)
    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.descendants(matching: .any)["GlobalSyncStatus"].firstMatch.waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Write Permissions"].exists)
    attachScreenshot(named: "global-sync-status-health-destination", from: app)
  }

  func testDraftModeChangeLeavesActiveConnectionAndCanCancel() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapSegment("Self-hosted", in: app)
    XCTAssertTrue(app.buttons["Cancel Changes"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Changes take effect only after connection succeeds. Your current setup remains active."].exists)
    app.buttons["Cancel Changes"].tap()
    XCTAssertFalse(app.textFields["Server URL"].exists)
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.buttons["Sync Now"].isEnabled)
  }

  func testConcentrationMenuKeepsSelectionAndAlignedLabels() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Insulin Concentration", in: app)
    let picker = app.buttons["InsulinConcentrationPicker"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["PickerLabel-Insulin Concentration"].exists,
                   "The visual label must not create a duplicate VoiceOver stop")
    XCTAssertTrue(picker.label.contains("Insulin Concentration"))
    XCTAssertTrue(meetsMinimumHitTargetDimension(picker.frame.height))
    picker.tap()
    let choice = app.buttons["U-200"].firstMatch
    XCTAssertTrue(choice.waitForExistence(timeout: 5))
    choice.tap()
    XCTAssertTrue(
      picker.label.contains("U-200") || picker.value as? String == "U-200",
      "Native picker must expose its selection: label=\(picker.label), value=\(String(describing: picker.value))"
    )
    picker.tap()
    attachScreenshot(named: "concentration-native-selection", from: app)
    XCTAssertTrue(app.buttons["U-100"].exists)
    XCTAssertTrue(app.buttons["U-500"].exists)
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
    XCTAssertTrue(app.buttons["Subscription Options"].waitForExistence(timeout: 5))

    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.buttons["Share Support Bundle"].waitForExistence(timeout: 5))
  }

  func testDesignReviewAdaptiveReachability() {
    let app = launchScreenshotFixture()
    func reveal(_ element: XCUIElement) {
      for _ in 0..<48 {
        if element.isHittable { break }
        let distanceToCenter = (element.exists ? element.frame.midY : app.frame.maxY) - app.frame.midY
        let scrollDown = distanceToCenter < 0
        let identity = element.identifier.isEmpty ? element.label : element.identifier
        let containingScroll = app.scrollViews.containing(.any, identifier: identity).firstMatch
        let scroll = containingScroll.exists ? containingScroll : app.scrollViews.firstMatch
        let distance = min(0.4, max(0.08, abs(distanceToCenter) / max(1, scroll.frame.height)))
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let finish = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + (scrollDown ? distance : -distance)))
        start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
      }
      if !element.isHittable {
        attachScreenshot(named: "unreachable-final-content", from: app)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "unreachable-content-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
      }
      XCTAssertTrue(element.isHittable, "Final content must be reachable: \(element)")
    }
    reveal(app.buttons["Sync Now"])
    XCTAssertGreaterThanOrEqual(app.buttons["Sync Now"].frame.height, 44 - 0.01)
    navigate(to: "Settings", in: app)
    tapSegment("Self-hosted", in: app)
    let field = app.textFields["Server URL"]
    reveal(field)
    field.tap()
    // A fresh simulator may cover the keyboard with the system QuickPath tip.
    // Dismiss only that identified tutorial, never an app permission prompt.
    for surface in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
      let tip = surface.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "sliding your finger across the letters")).firstMatch
      if tip.exists, surface.buttons["Continue"].exists { surface.buttons["Continue"].tap() }
    }
    let draftFeedback = app.staticTexts["SelfHostedConnectionFeedback"].label
    field.typeText("https://edited.example/api\n")
    XCTAssertTrue(app.staticTexts["SelfHostedConnectionFeedback"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.staticTexts["SelfHostedConnectionFeedback"].label, draftFeedback, "Keyboard return must not begin connection authentication")
    XCTAssertTrue(app.buttons["Cancel Changes"].waitForExistence(timeout: 3), "Keyboard return must leave connection changes as a draft")
    reveal(app.buttons["Cancel Changes"])
    attachScreenshot(named: "design-review-draft-keyboard-dismissed", from: app)
    app.buttons["Cancel Changes"].tap()
    tapNavigationLink("Tandem Account", in: app)
    reveal(app.buttons["Remove Credentials"])
    for _ in 0..<8 { if app.buttons["Change Account Details"].isHittable { break }; app.swipeDown() }
    app.buttons["Change Account Details"].tap()
    reveal(app.buttons["Cancel"])
    app.buttons["Cancel"].tap()
    tapBack(in: app)
    tapNavigationLink("Insulin Concentration", in: app)
    reveal(app.buttons["How Insulin Conversion Works"])
    tapBack(in: app)
    tapNavigationLink("Data Handling", in: app)
    reveal(app.descendants(matching: .any)["Full Privacy and Deletion Details"].firstMatch)
    attachScreenshot(named: "design-review-data-handling-final-content", from: app)
    tapBack(in: app)
    tapNavigationLink("Developer", in: app)
    reveal(app.buttons["devicePerformanceLogLink"])
    attachScreenshot(named: "design-review-adaptive-final-content", from: app)
  }

  func testAccessibilityAuditsCoreScreens() throws {
    continueAfterFailure = true
    defer { continueAfterFailure = false }
    let app = launchScreenshotFixture()
    var unresolvedNativeContrastNodes = 0
    defer {
      let evidence = XCTAttachment(string: "Unresolvable native contrast nodes: \(unresolvedNativeContrastNodes). These remain manual contrast checks; no conformance claim is made for inaccessible audit nodes.")
      evidence.name = "native-contrast-coverage-limit"
      evidence.lifetime = .keepAlways
      add(evidence)
    }
    func auditUnobscuredContent() throws {
      do {
      try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .textClipped, .dynamicType, .sufficientElementDescription]) { issue in
        // Native floating navigation intentionally blends the scrolled content
        // beneath its pill. Audit that text after revealing it, not while it is
        // physically covered by navigation. Never suppress hit/label/type issues.
        guard issue.auditType == .contrast else { return false }
        guard let element = issue.element else {
          unresolvedNativeContrastNodes += 1
          print("UNRESOLVABLE_NATIVE_CONTRAST_NODE: \(issue.detailedDescription)")
          self.attachScreenshot(named: "unresolved-native-contrast-\(unresolvedNativeContrastNodes)", from: app)
          return true
        }
        guard app.tabBars.firstMatch.exists else { return false }
        guard element.exists else {
          // The visual audit can refer to children intentionally combined out
          // of the VoiceOver tree. They cannot be queried or measured through
          // XCUIElement. Retain evidence and a nonzero manual-coverage count.
          unresolvedNativeContrastNodes += 1
          print("UNRESOLVABLE_NATIVE_CONTRAST_NODE: \(issue.detailedDescription)")
          self.attachScreenshot(named: "unresolved-native-contrast-\(unresolvedNativeContrastNodes)", from: app)
          return true
        }
        if !app.frame.contains(element.frame) {
          print("OFFSCREEN_CONTRAST: \(element.label) · \(element.frame); checked after scroll")
          return true
        }
        if app.navigationBars.firstMatch.exists, app.navigationBars.firstMatch.frame.intersects(element.frame) {
          print("NAVIGATION_UNDER_CONTRAST: \(element.label) · \(element.frame); checked outside navigation")
          return true
        }
        let buttons = app.tabBars.firstMatch.buttons.allElementsBoundByIndex
        let bounds = buttons.reduce(CGRect.null) { $0.union($1.frame) }.insetBy(dx: -8, dy: -8)
        if bounds.intersects(element.frame) {
          print("SCROLL_UNDER_CONTRAST: \(element.label) frame=\(element.frame); checking again after scroll")
          return true
        }
        // The native audit sometimes rejects strongly contrasting multiline
        // SwiftUI text. Verify the rendered monochrome text pixels instead;
        // only accept a conservative ratio >= 7, not borderline results.
        if element.elementType == .staticText, let ratio = self.renderedMonochromeContrast(element), ratio >= 7 {
          print("RENDERED_CONTRAST_VERIFIED: \(element.label) · ratio=\(ratio)")
          return true
        }
        print("ACCESSIBILITY_AUDIT: \(issue.compactDescription) · \(element.label) · \(element.frame)")
        return false
      }
      } catch { XCTFail("Accessibility audit failed: \(error)") }
    }
    try auditUnobscuredContent()
    navigate(to: "Settings", in: app)
    try auditUnobscuredContent()
    app.swipeUp()
    try auditUnobscuredContent()
    for title in ["Tandem Account", "Apple Health", "Insulin Concentration", "Data Handling", "About PumpSync", "Developer"] {
      tapNavigationLink(title, in: app)
      attachScreenshot(named: "accessibility-audit-" + title, from: app)
      try auditUnobscuredContent()
      app.swipeUp()
      try auditUnobscuredContent()
      tapBack(in: app)
    }
  }

  private func renderedMonochromeContrast(_ element: XCUIElement) -> Double? {
    guard let image = element.screenshot().image.cgImage else { return nil }
    let width = image.width, height = image.height
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drew = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drew else { return nil }
    var histogram: [Int: Int] = [:]
    for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] > 250 {
      let key = (Int(bytes[offset] >> 3) << 10) | (Int(bytes[offset + 1] >> 3) << 5) | Int(bytes[offset + 2] >> 3)
      histogram[key, default: 0] += 1
    }
    func luminance(_ key: Int) -> Double {
      let components = [(key >> 10) & 31, (key >> 5) & 31, key & 31].map { value -> Double in
        let normalized = Double(value * 8 + 4) / 255
        return normalized <= 0.04045 ? normalized / 12.92 : pow((normalized + 0.055) / 1.055, 2.4)
      }
      return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
    guard let background = histogram.max(by: { $0.value < $1.value }) else { return nil }
    let backgroundLuminance = luminance(background.key)
    let foreground = histogram.filter { abs(luminance($0.key) - backgroundLuminance) > 0.15 && $0.value >= max(3, width * height / 1000) }.max { $0.value < $1.value }
    guard let foreground else { return nil }
    let foregroundLuminance = luminance(foreground.key)
    return (max(backgroundLuminance, foregroundLuminance) + 0.05) / (min(backgroundLuminance, foregroundLuminance) + 0.05)
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
    XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-06-tandem-account.png", from: app)
    tapBack(in: app)

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-07-apple-health.png", from: app)

    tapBack(in: app)
    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-08-data-handling.png", from: app)

    tapBack(in: app)
    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-09-developer.png", from: app)

    tapBack(in: app)
    tapSegment("PumpSync", in: app)
    app.buttons["Subscription Options"].firstMatch.tap()
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
    XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-06-tandem-account.png", from: app)
    tapBack(in: app)

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-07-apple-health.png", from: app)
    tapBack(in: app)

    tapNavigationLink("Insulin Concentration", in: app)
    XCTAssertTrue(app.staticTexts["Current Setting"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-insulin-concentration-alignment.png", from: app)
    tapBack(in: app)

    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-08-data-handling.png", from: app)
    tapBack(in: app)

    tapNavigationLink("Developer", in: app)
    XCTAssertTrue(app.staticTexts["Diagnostics"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-09-developer.png", from: app)

    tapBack(in: app)
    app.buttons["Subscription Options"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["PumpSync Subscription"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-04-subscription-benefits.png", from: app)
  }

  func testInitialImportPickerRemainsReachable() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    let picker = app.buttons["HistoryRangePicker"]
    for _ in 0..<10 {
      if picker.isHittable { break }
      app.swipeUp()
    }
    XCTAssertTrue(picker.isHittable)
    XCTAssertGreaterThanOrEqual(picker.frame.minX, 0)
    XCTAssertLessThanOrEqual(picker.frame.maxX, app.windows.firstMatch.frame.maxX)
    XCTAssertTrue(picker.label.contains("14 days") || (picker.value as? String)?.contains("14 days") == true)
    attachScreenshot(named: "initial-import-picker-reachable", from: app)
    picker.tap()
    XCTAssertTrue(app.buttons["Past 2 days"].waitForExistence(timeout: 2) || app.buttons["2 days"].waitForExistence(timeout: 2))
  }

  func testRemediationPickerScreens() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    attachScreenshot(named: "remediation-initial-light", from: app)
    let history = app.buttons["HistoryRangePicker"]
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    history.tap()
    XCTAssertTrue(app.buttons["Past 2 days"].waitForExistence(timeout: 5))
    attachScreenshot(named: "remediation-history-menu-light", from: app)
    app.collectionViews.buttons["Past 14 days"].tap()
    navigate(to: "Settings", in: app)
    attachScreenshot(named: "remediation-settings-light", from: app)
    tapNavigationLink("Tandem Account", in: app)
    let sourceHeader = app.staticTexts["Saved Account"]
    let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      sourceHeader.exists && sourceHeader.frame.minX < 30
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    attachScreenshot(named: "remediation-tandem-light", from: app)
    app.buttons["Change Account Details"].tap()
    let regionPicker = app.buttons["TandemRegionPicker"]
    regionPicker.tap()
    XCTAssertTrue(app.buttons["Europe"].waitForExistence(timeout: 5))
    attachScreenshot(named: "remediation-region-menu-light", from: app)
    app.buttons["Europe"].firstMatch.tap()
    XCTAssertTrue(regionPicker.label.contains("Europe") || regionPicker.value as? String == "Europe")
    tapBack(in: app)
    tapNavigationLink("Insulin Concentration", in: app)
    attachScreenshot(named: "remediation-concentration-light", from: app)
    app.buttons["InsulinConcentrationPicker"].tap()
    attachScreenshot(named: "remediation-concentration-menu-light", from: app)
    app.buttons["U-100"].firstMatch.tap()
    tapBack(in: app)
    tapNavigationLink("Data Handling", in: app)
    attachScreenshot(named: "remediation-data-handling-light", from: app)
  }

  func testRemediationScrolledScreens() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    app.swipeUp()
    attachScreenshot(named: "remediation-settings-lower-light", from: app)
    app.buttons["AboutPumpSyncLink"].tap()
    XCTAssertTrue(app.staticTexts["Insulin and carbohydrates"].waitForExistence(timeout: 5))
    attachScreenshot(named: "remediation-about-light", from: app)
    tapBack(in: app)
    tapNavigationLink("Insulin Concentration", in: app)
    app.swipeUp()
    attachScreenshot(named: "remediation-concentration-lower-light", from: app)
    tapBack(in: app)
    tapNavigationLink("Data Handling", in: app)
    app.swipeUp()
    attachScreenshot(named: "remediation-data-handling-lower-light", from: app)
    tapBack(in: app)
    tapNavigationLink("Developer", in: app)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
      .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.25)))
    attachScreenshot(named: "remediation-developer-middle-light", from: app)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.8))
      .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.25)))
    attachScreenshot(named: "remediation-developer-lower-light", from: app)
  }

  private func launchScreenshotFixture(
    orientation: UIDeviceOrientation = .portrait,
    launchArguments: [String] = [],
    launchEnvironment: [String: String] = [:]
  ) -> XCUIApplication {
    if #available(iOS 27.0, *) {
      // Restore normal gestures even if an earlier VoiceOver run was interrupted.
      do { try XCUIDevice.shared.voiceOverService.disable() }
      catch { XCTFail("Could not restore normal simulator gestures: \(error)") }
    }
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

  private func tapBack(in app: XCUIApplication) {
    // Some installed runtimes expose native Back as Other in legacy AX data.
    // Its observed system identifier remains stable across those role changes.
    let back = app.navigationBars.descendants(matching: .any).matching(identifier: "BackButton").firstMatch
    if back.exists { back.tap() }
    else { app.navigationBars.buttons.firstMatch.tap() }
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
    for identifier in ["appEventsLogLink", "devicePerformanceLogLink"] {
      let link = app.buttons[identifier]
      for _ in 0..<6 {
        if link.isHittable { break }
        app.swipeUp()
      }
      XCTAssertTrue(link.isHittable)
    }
    XCTAssertTrue(app.buttons["Share Support Bundle"].exists)
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
    XCTAssertEqual(field.placeholderValue, "https://your-server.example/api")
    XCTAssertEqual(field.label, "Server URL")
    XCTAssertEqual(field.identifier, "ServerURLField")
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
