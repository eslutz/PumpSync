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
      app.navigationBars.buttons.firstMatch.tap()
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
    app.navigationBars.buttons.firstMatch.tap()
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
    app.navigationBars.buttons.firstMatch.tap()
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
    app.navigationBars.buttons.firstMatch.tap()
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
        XCTAssertFalse(speech.contains("Region"), "The visual Region label must not create another focus stop")
        let regionSpeech = try XCTUnwrap(speech.first { $0.contains("Tandem region") })
        XCTAssertEqual(regionSpeech.components(separatedBy: "United States").count - 1, 1)
      }
      if title == "Insulin Concentration" {
        let concentrationSpeech = try XCTUnwrap(speech.first { $0.contains("U-100") })
        XCTAssertEqual(concentrationSpeech.components(separatedBy: "U-100").count - 1, 1)
      }
      try voiceOver.disable()
      app.navigationBars.buttons.firstMatch.tap()
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
      XCTAssertFalse(app.buttons["CopyDiagnosticsLog"].isEnabled)
      try voiceOver.disable()
      app.navigationBars.buttons.firstMatch.tap()
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
    navigate(to: "Settings", in: app)
    XCTAssertFalse(app.staticTexts["Sync needs attention"].exists)
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["Sync needs attention"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Sync Now"].exists)
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

  func testDiagnosticsNavigationCopyAndClear() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Developer", in: app)
    for identifier in ["appEvents", "devicePerformance"] {
      let link = app.buttons[identifier + "LogLink"]
      for _ in 0..<8 {
        if link.isHittable { break }
        app.swipeUp()
      }
      XCTAssertTrue(link.isHittable)
      attachScreenshot(named: identifier + "-overview", from: app)
      link.tap()
      let copy = app.buttons["CopyDiagnosticsLog"]
      XCTAssertTrue(copy.waitForExistence(timeout: 5))
      XCTAssertTrue(copy.isEnabled)
      attachScreenshot(named: identifier + "-records", from: app)
      copy.tap()
      app.buttons["DiagnosticsLogActions"].tap()
      app.buttons["Clear Logs"].firstMatch.tap()
      XCTAssertTrue(app.staticTexts["Clear Logs?"].waitForExistence(timeout: 3))
      attachScreenshot(named: identifier + "-clear-confirmation", from: app)
      app.buttons["Cancel"].tap()
      XCTAssertTrue(app.buttons["Clear Logs"].waitForNonExistence(timeout: 3))
      XCTAssertTrue(copy.isEnabled)
      app.buttons["DiagnosticsLogActions"].tap()
      app.buttons["Clear Logs"].firstMatch.tap()
      app.buttons["Clear Logs"].firstMatch.tap()
      XCTAssertTrue(app.staticTexts["EmptyDiagnosticsLog"].waitForExistence(timeout: 5))
      XCTAssertFalse(copy.isEnabled)
      attachScreenshot(named: identifier + "-empty", from: app)
      app.navigationBars.buttons.firstMatch.tap()
      XCTAssertTrue(link.waitForExistence(timeout: 5))
    }
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
    let sourceHeader = app.staticTexts["Tandem Source"]
    let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      sourceHeader.exists && sourceHeader.frame.minX < 30
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
    attachScreenshot(named: "remediation-tandem-light", from: app)
    let regionPicker = app.buttons["TandemRegionPicker"]
    regionPicker.tap()
    XCTAssertTrue(app.buttons["Europe"].waitForExistence(timeout: 5))
    attachScreenshot(named: "remediation-region-menu-light", from: app)
    app.buttons["Europe"].firstMatch.tap()
    XCTAssertTrue(regionPicker.label.contains("Europe") || regionPicker.value as? String == "Europe")
    app.navigationBars.buttons.firstMatch.tap()
    tapNavigationLink("Insulin Concentration", in: app)
    attachScreenshot(named: "remediation-concentration-light", from: app)
    app.buttons["InsulinConcentrationPicker"].tap()
    attachScreenshot(named: "remediation-concentration-menu-light", from: app)
    app.buttons["U-100"].firstMatch.tap()
    app.navigationBars.buttons.firstMatch.tap()
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
    app.navigationBars.buttons.firstMatch.tap()
    tapNavigationLink("Insulin Concentration", in: app)
    app.swipeUp()
    attachScreenshot(named: "remediation-concentration-lower-light", from: app)
    app.navigationBars.buttons.firstMatch.tap()
    tapNavigationLink("Data Handling", in: app)
    app.swipeUp()
    attachScreenshot(named: "remediation-data-handling-lower-light", from: app)
    app.navigationBars.buttons.firstMatch.tap()
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
