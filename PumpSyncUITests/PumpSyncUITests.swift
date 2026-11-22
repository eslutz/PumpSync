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
      tapNavigationLink("Support & Diagnostics", in: app)
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
      if state == "populated" {
        let range = app.buttons["Time range"]
        revealFormControl(range, in: app)
        range.tap()
        XCTAssertTrue(app.staticTexts["Newest"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Oldest"].exists)
        XCTAssertTrue(app.staticTexts["Time zone"].exists)
        attachScreenshot(named: "review-source-" + state + "-range", from: app)
      } else {
        XCTAssertFalse(app.buttons["Time range"].exists)
        XCTAssertFalse(app.staticTexts["0 records"].exists)
      }
      tapBack(in: app)
      XCTAssertTrue(app.navigationBars["Support & Diagnostics"].exists)
      if state == "populated" {
        let log = app.buttons["appEventsLogLink"]
        scrollTo(log, in: app)
        log.tap()
        let readyEvent = app.buttons.matching(NSPredicate(
          format: "label CONTAINS %@ AND label CONTAINS %@", "Import preview", "records available")).firstMatch
        revealFormControl(readyEvent, in: app)
        XCTAssertTrue(readyEvent.isHittable)
        readyEvent.tap()
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Records available"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "purpose=real")).firstMatch.exists)
        attachScreenshot(named: "review-import-preview-readable-event", from: app)
      }
      app.terminate()
    }
  }

  func testSourceDataLoadingCanCancelAndNavigateBack() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-preview", "loading"])
    navigate(to: "Settings", in: app)
    tapNavigationLink("Support & Diagnostics", in: app)
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
    XCTAssertTrue(app.navigationBars["Support & Diagnostics"].exists)
  }

  @available(iOS 27.0, *)
  func testVoiceOverSourceDataRefreshAndHealthInstructions() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-preview", "populated"])
    navigate(to: "Settings", in: app)
    tapNavigationLink("Apple Health", in: app)
    let instructions = app.buttons["How to Change Access"]
    revealFormControl(instructions, in: app)
    instructions.tap()
    attachScreenshot(named: "review-health-instructions", from: app)
    try enableVoiceOver()
    let healthSpeech = try recordVoiceOverScreen("health-updated-instructions", maximum: 24)
    XCTAssertTrue(healthSpeech.contains { $0.contains("Open Health") })
    try voiceOver.disable()
    tapBack(in: app)
    tapNavigationLink("Support & Diagnostics", in: app)
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
    let speech = try recordVoiceOverScreen("sync-ready", maximum: 24)
    XCTAssertEqual(speech.filter { $0.localizedCaseInsensitiveContains("last synced") }.count, 1)
    XCTAssertEqual(speech.filter { $0.localizedCaseInsensitiveContains("48 samples saved") }.count, 1)
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
    let actionIndex = try XCTUnwrap(initialSpeech.firstIndex { $0.contains("Sync Past 14 Days") })
    let rangeIndex = try XCTUnwrap(initialSpeech.firstIndex(of: historySpeech))
    XCTAssertLessThan(rangeIndex, actionIndex)
    try focusVoiceOver("History range")
    app.buttons["HistoryRangePicker"].doubleTap()
    XCTAssertTrue(app.buttons["Past 7 days"].waitForExistence(timeout: 5))
    try recordVoiceOverScreen("history-menu", maximum: 10)
    try focusVoiceOver("Past 7 days", backwards: true)
    app.buttons["Past 7 days"].doubleTap()
    XCTAssertTrue(app.buttons["HistoryRangePicker"].waitForExistence(timeout: 5))
    try focusVoiceOver("Settings Tab")
    app.tabBars.buttons["Settings"].doubleTap()
    XCTAssertTrue(app.buttons["TandemAccountLink"].waitForExistence(timeout: 5))
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
    XCTAssertTrue(app.buttons["U-200"].waitForExistence(timeout: 5))
    try focusVoiceOver("U-200")
    app.buttons["U-200"].firstMatch.doubleTap()
    XCTAssertTrue(app.buttons["U-200"].firstMatch.isSelected)
    try focusVoiceOver("Insulin Concentration")
    XCTAssertTrue(try voiceOver.currentSpeech().utterance.contains("Heading"))
    try focusVoiceOver("U-200", alsoContaining: "Selected")
    let concentrationSpeech = try voiceOver.currentSpeech().utterance
    print("VOICEOVER concentration-selected: \(concentrationSpeech)")
    XCTAssertEqual(concentrationSpeech.components(separatedBy: "U-200").count - 1, 1)
    XCTAssertTrue(concentrationSpeech.localizedCaseInsensitiveContains("selected"))
    attachScreenshot(named: "voiceover-picker-selections", from: app)
  }

  @available(iOS 27.0, *)
  func testVoiceOverSettingsDestinations() throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    defer { try? voiceOver.disable() }
    try voiceOver.disable()
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    for title in ["Tandem Account", "Apple Health", "Insulin Concentration", "Data Handling", "About PumpSync", "Support & Diagnostics"] {
      tapNavigationLink(title, in: app)
      var installationIDPrefix: String?
      if title == "Support & Diagnostics" {
        let row = app.staticTexts["InstallationIDRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let label = row.label
        let identifierRange = try XCTUnwrap(label.range(
          of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
          options: .regularExpression))
        installationIDPrefix = String(label[identifierRange].prefix(8))
      }
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
      if let installationIDPrefix {
        let installationSpeech = try XCTUnwrap(speech.first { $0.hasPrefix("Installation ID") })
        // Apple's speech snapshot may truncate the second UUID. Its prefix
        // still detects the duplicated native label/value announcement.
        XCTAssertEqual(installationSpeech.components(separatedBy: installationIDPrefix).count - 1, 1)
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
    tapNavigationLink("Support & Diagnostics", in: app)
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
      app.buttons["ClearDiagnosticsLog"].firstMatch.tap()
      try enableVoiceOver()
      try recordVoiceOverScreen(title + "-confirmation", maximum: 6)
      try focusVoiceOver("Cancel", backwards: true)
      app.buttons["Cancel"].doubleTap()
      XCTAssertTrue(app.buttons["ClearDiagnosticsLog"].waitForNonExistence(timeout: 5))
      try focusVoiceOver("Log Actions")
      app.buttons["DiagnosticsLogActions"].doubleTap()
      try focusVoiceOver(title == "App Event Log" ? "Clear App Events" : "Clear Performance Reports")
      app.buttons["ClearDiagnosticsLog"].firstMatch.doubleTap()
      try focusVoiceOver(title == "App Event Log" ? "Clear App Events" : "Clear Performance Reports")
      app.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Clear ")).firstMatch.doubleTap()
      XCTAssertTrue(app.descendants(matching: .any)["EmptyDiagnosticsLog"].firstMatch.waitForExistence(timeout: 5))
      let emptySpeech = try recordVoiceOverScreen(title + "-empty", maximum: 12)
      XCTAssertTrue(emptySpeech.contains { $0.contains("No ") })
      try voiceOver.disable()
      app.buttons["DiagnosticsLogActions"].tap()
      XCTAssertFalse(app.buttons["CopyDiagnosticsLog"].isEnabled)
      dismissLogActions(in: app)
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
    if try focusedSpeech().contains("VoiceOver Gestures") {
      // A fresh simulator can show Apple's one-time introduction. Turning the
      // service off dismisses it; it is not part of the application's flow.
      try service.disable()
      try service.enable()
      _ = try focusedSpeech()
    }
    XCTAssertTrue(service.isEnabled)
  }

  @available(iOS 27.0, *)
  private func focusedSpeech() throws -> String {
    let service = XCUIDevice.shared.voiceOverService
    do {
      return try service.currentSpeech().utterance
    } catch let error as XCUIVoiceOverService.Error where error.code == .noSpeech {
      // Enabling the service does not guarantee an element has focus yet.
      // A VoiceOver navigation gesture establishes focus and returns its speech.
      return try service.moveForward().utterance
    }
  }

  @available(iOS 27.0, *)
  @discardableResult
  private func recordVoiceOverScreen(_ name: String, maximum: Int = 30) throws -> [String] {
    let voiceOver = XCUIDevice.shared.voiceOverService
    var first = try focusedSpeech()
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
  private func focusVoiceOver(_ text: String, alsoContaining additionalText: String? = nil,
                             backwards: Bool = false) throws {
    let voiceOver = XCUIDevice.shared.voiceOverService
    var speech = try focusedSpeech()
    var reverse = backwards
    var reachedBoundary = false
    for _ in 0..<65 {
      if speech.contains(text) {
        if additionalText != nil { print("VOICEOVER matching \(text): \(speech)") }
        if additionalText.map({ speech.localizedCaseInsensitiveContains($0) }) ?? true { return }
      }
      let next = try reverse ? voiceOver.moveBackward().utterance : voiceOver.moveForward().utterance
      if next == speech {
        if reachedBoundary { break }
        reachedBoundary = true
        reverse.toggle()
      }
      speech = next
    }
    let requiredText = additionalText.map { "\(text) and \($0)" } ?? text
    XCTFail("VoiceOver could not reach \(requiredText); last speech: \(speech)")
  }

  func testPreviewEntryPointsLiveOnlyInDiagnostics() {
    let app = launchScreenshotFixture()
    XCTAssertFalse(app.buttons["Preview Import"].exists)
    navigate(to: "Settings", in: app)
    XCTAssertFalse(app.buttons["Sample Preview"].exists)
    tapNavigationLink("Support & Diagnostics", in: app)
    let inspect = app.buttons["Inspect source data"]
    if !inspect.isHittable { app.swipeUp() }
    XCTAssertTrue(inspect.waitForExistence(timeout: 5))
    inspect.tap()
    XCTAssertTrue(app.staticTexts["PreviewSafetyNotice"].waitForExistence(timeout: 5))
  }

  func testConnectionRecoveryOpensTandemAccount() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-connection-failure"])
    let recovery = app.buttons["SyncNowButton"]
    revealFormControl(recovery, in: app)
    XCTAssertEqual(recovery.label, "Reconnect to Tandem")
    XCTAssertTrue(meetsMinimumHitTargetDimension(recovery.frame.height))
    attachScreenshot(named: "connection-recovery", from: app)
    recovery.tap()
    XCTAssertTrue(app.navigationBars["Tandem"].waitForExistence(timeout: 5))
    let edit = app.buttons["Change Account Details"]
    revealFormControl(edit, in: app)
    XCTAssertTrue(edit.isHittable)
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
    let completion = app.staticTexts["Open Sync Details for counts and times. Previously imported records are skipped to prevent duplicates."]
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

  func testInlineProgressPersistsAcrossTabNavigationWithoutStatusSheet() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-syncing"])
    let action = app.buttons["SyncNowButton"]
    revealFormControl(action, in: app)
    XCTAssertFalse(action.isEnabled)
    let detail = app.staticTexts["SyncProgressDetail"]
    revealFormControl(detail, in: app)
    XCTAssertTrue(detail.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["SyncStatusButton"].exists)
    XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
    XCTAssertFalse(app.navigationBars["Sync Details"].exists)
    attachScreenshot(named: "sync-inline-progress", from: app)
    navigate(to: "Settings", in: app)
    XCTAssertFalse(app.buttons["SyncStatusButton"].exists)
    XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
    navigate(to: "Sync", in: app)
    revealFormControl(action, in: app)
    XCTAssertFalse(action.isEnabled)
    revealFormControl(detail, in: app)
    XCTAssertTrue(detail.isHittable)
  }

  func testSuccessSummaryPersistsAcrossNavigation() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-sync-success"])
    let heading = app.staticTexts["SyncProgressTitle"]
    let summary = app.staticTexts["SyncProgressDetail"]
    XCTAssertTrue(heading.waitForExistence(timeout: 5))
    XCTAssertTrue(heading.label.localizedCaseInsensitiveContains("last synced"))
    XCTAssertEqual(summary.label, "4 samples saved to Apple Health")
    XCTAssertFalse(app.staticTexts["SyncRecordsReceived"].exists)
    XCTAssertFalse(app.staticTexts["Connection"].exists)
    XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
    let details = app.buttons["SyncDetailsLink"]
    revealFormControl(details, in: app)
    details.tap()
    XCTAssertTrue(app.navigationBars["Sync Details"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.staticTexts["SyncRecordsReceived"].label, "Records received, 48")
    XCTAssertEqual(app.staticTexts["SyncSamplesSaved"].label, "Samples saved, 4")
    attachScreenshot(named: "sync-details", from: app)
    tapBack(in: app)
    navigate(to: "Settings", in: app)
    navigate(to: "Sync", in: app)
    XCTAssertTrue(summary.waitForExistence(timeout: 5))
    XCTAssertEqual(summary.label, "4 samples saved to Apple Health")
    attachScreenshot(named: "inline-sync-success", from: app)
  }

  func testCompletionNoticeAppearsOnlyOnceOnSync() {
    let app = launchScreenshotFixture(launchArguments: [
      "--pumpsync-screenshot-sync-success", "--pumpsync-screenshot-sync-notice"
    ])
    let notice = app.staticTexts["SyncCompletionDetail"]
    revealFormControl(notice, in: app)
    XCTAssertFalse(notice.label.isEmpty)
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", notice.label)).count, 1)
    XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
    let primary = app.buttons["SyncNowButton"]
    revealFormControl(primary, in: app)
    XCTAssertEqual(primary.label, "Review Health Access")
    primary.tap()
    XCTAssertTrue(app.navigationBars["Apple Health"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["PartialHealthAccessNotice"].exists)
    tapBack(in: app)
    let details = app.buttons["SyncDetailsLink"]
    revealFormControl(details, in: app)
    details.tap()
    let allowedTypes = app.buttons["Sync Allowed Types"]
    revealFormControl(allowedTypes, in: app)
    XCTAssertTrue(allowedTypes.isEnabled)
    tapBack(in: app)
    navigate(to: "Settings", in: app)
    XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
    navigate(to: "Sync", in: app)
    revealFormControl(notice, in: app)
    XCTAssertTrue(notice.isHittable)
  }

  func testFeedbackTransitionsKeepOnePrimaryAction() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-feedback-sequence"])
    let advance = app.buttons["AdvanceFeedbackFixture"]
    XCTAssertTrue(advance.wait(for: \.isHittable, toEqual: true, timeout: 5))
    assertFeedbackSystemTextSize(advance)
    for (step, title) in [(1, "Preparing sync…"), (2, "Downloading pump data…"), (3, "Updating Apple Health…")] {
      advanceFeedback(to: step, title: title, in: app)
      let action = app.buttons["SyncNowButton"]
      revealFormControl(action, in: app)
      XCTAssertFalse(action.isEnabled)
      XCTAssertEqual(action.label, "Syncing")
      XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
    }
    advanceFeedback(to: 4, title: nil, in: app)
    let retry = app.buttons["SyncNowButton"]
    revealFormControl(retry, in: app)
    XCTAssertEqual(retry.label, "Try Again")
    XCTAssertTrue(retry.isEnabled)
    XCTAssertFalse(app.buttons["Sync Now"].exists)
    XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
    attachScreenshot(named: "sync-single-recovery-action", from: app)
  }

  func testFeedbackTextAndActionsRemainReachableAtSystemTextSize() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-feedback-sequence"])
    let advance = app.buttons["AdvanceFeedbackFixture"]
    XCTAssertTrue(advance.wait(for: \.isHittable, toEqual: true, timeout: 5))
    assertFeedbackSystemTextSize(advance)
    for step in 1...7 { advanceFeedback(to: step, title: nil, in: app) }
    let notice = app.staticTexts["SyncCompletionDetail"]
    let bodyHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
    // Move just the form. The final line must be readable above the system tab bar.
    let form = app.collectionViews.firstMatch
    for _ in 0..<32 {
      let viewport = feedbackVisibleContent(in: app)
      if notice.exists, notice.frame.maxY <= viewport.maxY + 0.5,
         notice.frame.maxY >= viewport.minY + bodyHeight { break }
      let moveDown = !notice.exists || notice.frame.maxY > viewport.maxY
      let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
      let finish = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: moveDown ? 0.35 : 0.75))
      start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    let viewport = feedbackVisibleContent(in: app)
    XCTAssertTrue(notice.exists)
    XCTAssertLessThanOrEqual(notice.frame.maxY, viewport.maxY + 0.5)
    XCTAssertGreaterThanOrEqual(notice.frame.maxY, viewport.minY + bodyHeight)
    XCTAssertGreaterThanOrEqual(notice.frame.height, bodyHeight * 0.85)
    attachScreenshot(named: "feedback-notice-final-line", from: app)
    let action = app.buttons["SyncNowButton"]
    revealFormControl(action, in: app)
    XCTAssertTrue(action.isHittable)
    XCTAssertTrue(meetsMinimumHitTargetDimension(action.frame.height))
  }

  private func assertFeedbackSystemTextSize(_ advance: XCUIElement) {
    let category = UIApplication.shared.preferredContentSizeCategory.rawValue
    let appCategory = (advance.value as? String)?.split(separator: "|").last.map(String.init)
    XCTAssertEqual(appCategory, category, "App and test runner must use the actual system text category")
    let evidence = "SYNC_FEEDBACK_TYPOGRAPHY category=\(category) appCategory=\(appCategory ?? "missing") bodyLineHeight=\(UIFont.preferredFont(forTextStyle: .body).lineHeight)"
    print(evidence)
    let attachment = XCTAttachment(string: evidence)
    attachment.name = "feedback-system-text-size"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func advanceFeedback(to step: Int, title: String?, in app: XCUIApplication) {
    let control = app.buttons["AdvanceFeedbackFixture"]
    XCTAssertTrue(control.isHittable)
    control.tap()
    let predicate = NSPredicate(format: "value BEGINSWITH %@", "\(step)|")
    let advanced = XCTNSPredicateExpectation(predicate: predicate, object: control)
    XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 5), .completed)
    if let title {
      XCTAssertTrue(app.staticTexts["SyncProgressTitle"].wait(for: \.label, toEqual: title, timeout: 5))
    }
  }

  private func feedbackVisibleContent(in app: XCUIApplication) -> CGRect {
    let frame = app.frame
    let navigation = app.navigationBars.firstMatch
    let tabs = app.tabBars.firstMatch
    let top = navigation.exists ? max(frame.minY, navigation.frame.maxY) : frame.minY
    let bottom = tabs.exists && tabs.frame.midY > frame.midY ? min(frame.maxY, tabs.frame.minY) : frame.maxY
    return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, bottom - top))
  }

  func testInitialImportRangeControlsTheActionAndLocksWhileRunning() {
    let ready = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    let range = ready.buttons["HistoryRangePicker"]
    let action = ready.buttons["SyncNowButton"]
    XCTAssertTrue(range.waitForExistence(timeout: 5))
    XCTAssertLessThan(range.frame.minY, action.frame.minY)
    range.tap()
    ready.buttons["Past 7 days"].firstMatch.tap()
    XCTAssertEqual(action.label, "Sync Past 7 Days")
    ready.terminate()
    let running = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync", "--pumpsync-screenshot-syncing"])
    let runningRange = running.buttons["HistoryRangePicker"]
    XCTAssertFalse(runningRange.exists && runningRange.isEnabled)
    XCTAssertFalse(running.buttons["SyncNowButton"].isEnabled)
    attachScreenshot(named: "first-import-in-progress", from: running)
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

  func testCoreScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture()

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))
    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["SyncProgressTitle"].waitForExistence(timeout: 5))
    let recordedSummary = app.staticTexts["SyncProgressDetail"]
    XCTAssertTrue(recordedSummary.waitForExistence(timeout: 3), "Recorded success must remain visible without a transient completion state")
    XCTAssertEqual(recordedSummary.label, "48 samples saved to Apple Health")

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.buttons["TandemAccountLink"].waitForExistence(timeout: 5))

    tapNavigationLink("Tandem Account", in: app)
    XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 5))
    tapBack(in: app)

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    attachScreenshot(named: "review-health-native-permission-rows", from: app)
    tapBack(in: app)

    tapNavigationLink("Data Handling", in: app)
    XCTAssertTrue(app.staticTexts["Pump Data"].waitForExistence(timeout: 5))
    scrollTo(app.buttons["Email Deletion Request"], in: app)
    attachScreenshot(named: "review-data-deletion-native-actions", from: app)
    scrollTo(app.descendants(matching: .any)["Privacy and Deletion Details"].firstMatch, in: app)
    attachScreenshot(named: "review-data-deletion-footer", from: app)
    tapBack(in: app)

    tapNavigationLink("Support & Diagnostics", in: app)
    assertDeveloperDiagnosticsVisible(in: app)
    attachScreenshot(named: "review-developer-native-diagnostics", from: app)
  }

  func testInstallationIDCopiesFromExplicitAction() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Support & Diagnostics", in: app)
    let row = app.staticTexts["InstallationIDRow"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let installationLabel = row.label
    XCTAssertTrue(installationLabel.contains("Installation ID"))
    let identifierRange = installationLabel.range(
      of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
      options: .regularExpression)
    XCTAssertNotNil(identifierRange, "The native row must include its installation UUID")
    let copy = app.buttons["Copy Installation ID"].firstMatch
    XCTAssertTrue(copy.waitForExistence(timeout: 5))
    copy.tap()
    XCTAssertTrue(app.buttons["Installation ID Copied"].waitForExistence(timeout: 3))
    XCTAssertEqual(row.label, installationLabel)
    attachScreenshot(named: "installation-id-copied", from: app)
  }

  func testDeveloperDiagnosticsActionsUseUniqueAccessibleNames() {
    let app = launchScreenshotFixture()

    navigate(to: "Settings", in: app)
    tapNavigationLink("Support & Diagnostics", in: app)

    assertDeveloperDiagnosticsVisible(in: app)
  }

  func testDiagnosticsNavigationCopyAndClear() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Support & Diagnostics", in: app)
    for identifier in ["appEvents", "devicePerformance"] {
      let link = app.buttons[identifier + "LogLink"]
      for _ in 0..<8 { if link.isHittable { break }; app.swipeUp() }
      XCTAssertTrue(link.isHittable)
      link.tap()
      let title = identifier == "appEvents" ? "App Event Log" : "Performance"
      XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
      let actions = app.buttons["DiagnosticsLogActions"]
      XCTAssertTrue(actions.wait(for: \.isHittable, toEqual: true, timeout: 5))
      attachScreenshot(named: identifier + "-summary", from: app)
      actions.tap()
      let copy = app.buttons["CopyDiagnosticsLog"]
      XCTAssertTrue(copy.waitForExistence(timeout: 3))
      XCTAssertTrue(copy.isEnabled)
      copy.tap()
      app.buttons["DiagnosticsLogActions"].tap()
      XCTAssertEqual(app.buttons["CopyDiagnosticsLog"].label,
                     identifier == "appEvents" ? "All App Events Copied" : "All Performance Reports Copied")
      app.buttons["ClearDiagnosticsLog"].firstMatch.tap()
      XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
      attachScreenshot(named: identifier + "-clear-confirmation", from: app)
      app.buttons["Cancel"].tap()
      XCTAssertFalse(app.descendants(matching: .any)["EmptyDiagnosticsLog"].firstMatch.exists)
      app.buttons["DiagnosticsLogActions"].tap()
      app.buttons["ClearDiagnosticsLog"].firstMatch.tap()
      XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
      app.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Clear ")).firstMatch.tap()
      XCTAssertTrue(app.descendants(matching: .any)["EmptyDiagnosticsLog"].firstMatch.waitForExistence(timeout: 5))
      app.buttons["DiagnosticsLogActions"].tap()
      XCTAssertFalse(app.buttons["CopyDiagnosticsLog"].isEnabled)
      dismissLogActions(in: app)
      tapBack(in: app)
      XCTAssertTrue(link.waitForExistence(timeout: 5))
    }
  }

  func testSavedAccountEditingBackPreservesSavedSummary() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Tandem Account", in: app)
    XCTAssertTrue(app.staticTexts["Saved Account"].exists)
    XCTAssertFalse(app.secureTextFields["Tandem password"].exists)
    app.buttons["Change Account Details"].tap()
    let password = app.secureTextFields["Tandem password"]
    XCTAssertTrue(password.waitForExistence(timeout: 3))
    XCTAssertEqual(password.value as? String, "Password")
    password.tap()
    password.typeText("unsaved-password\n")
    tapBack(in: app)
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Tandem"].waitForNonExistence(timeout: 5))
    reopenTandemAfterDiscardingPassword(using: app.buttons["TandemAccountLink"], in: app)
    XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 3))
    XCTAssertFalse(password.exists)
    XCTAssertTrue(app.buttons["Remove Account"].exists)
  }

  func testActionableFailureArrivingInSettingsCanBeReviewedOnSync() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-feedback-sequence"])
    navigate(to: "Settings", in: app)
    tapNavigationLink("Apple Health", in: app)
    for step in 1...4 { advanceFeedback(to: step, title: nil, in: app) }
    let review = app.buttons["SyncMessageActionButton"]
    XCTAssertTrue(review.wait(for: \.isHittable, toEqual: true, timeout: 5))
    XCTAssertEqual(review.label, "Review Sync")
    XCTAssertTrue(meetsMinimumHitTargetDimension(review.frame.height))
    dismissSyncMessage(in: app)
    XCTAssertTrue(app.navigationBars["Apple Health"].exists)
    for step in 5...6 { advanceFeedback(to: step, title: nil, in: app) }
    XCTAssertTrue(review.wait(for: \.isHittable, toEqual: true, timeout: 5))
    review.tap()
    XCTAssertTrue(app.buttons["SyncNowButton"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["SyncNowButton"].label, "Try Again")
    XCTAssertFalse(review.exists)
    XCTAssertFalse(app.buttons["DismissSyncMessageButton"].exists)
  }

  func testFreshInstallConnectsDirectlyFromSync() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-new-account"])
    let account = app.buttons["Connect to Tandem"]
    XCTAssertTrue(account.wait(for: \.isHittable, toEqual: true, timeout: 5))
    XCTAssertFalse(app.buttons["Sync Now"].exists)
    attachScreenshot(named: "setup", from: app)
    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.buttons["TandemAccountLink"].exists)
    XCTAssertFalse(app.buttons["SubscriptionSettingsLink"].exists)
    XCTAssertFalse(app.textFields["Server URL"].exists)
    tapNavigationLink("Data Handling", in: app)
    XCTAssertFalse(app.buttons["Email Deletion Request"].exists)
    navigate(to: "Sync", in: app)
    account.tap()
    let username = app.textFields["Tandem username"]
    username.tap()
    username.typeText("fixture@example.invalid\n")
    let password = app.secureTextFields["Tandem password"]
    password.tap()
    password.typeText("fixture-only\n")
    let save = app.buttons["Connect Account"]
    revealFormControl(save, in: app)
    save.tap()
    XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Change Account Details"].exists)
    attachScreenshot(named: "direct-tandem-account-connected", from: app)
  }

  func testUpgradedAccountRequiresExplicitReconnect() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-legacy-account"])
    let reconnect = app.buttons["Reconnect to Tandem"]
    XCTAssertFalse(app.buttons["Sync Now"].exists)
    XCTAssertTrue(reconnect.wait(for: \.isHittable, toEqual: true, timeout: 5))
    attachScreenshot(named: "setup-reconnect", from: app)
    reconnect.tap()
    XCTAssertTrue(app.navigationBars["Tandem"].waitForExistence(timeout: 5))
    reconnect.tap()
    XCTAssertTrue(reconnect.waitForNonExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Saved Account"].exists)
    tapBack(in: app)
    XCTAssertTrue(app.buttons["Sync Past 14 Days"].isEnabled)
  }

  func testSyncShowsHealthSetupBeforeAnUnavailableImport() {
    let app = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-health-setup", "--pumpsync-screenshot-initial-sync"])
    let health = app.buttons["Set Up Apple Health"]
    XCTAssertTrue(health.wait(for: \.isHittable, toEqual: true, timeout: 5))
    XCTAssertFalse(app.buttons["Sync Now"].exists)
    attachScreenshot(named: "setup-health", from: app)
    health.tap()
    XCTAssertTrue(app.buttons["Allow Access to Health"].waitForExistence(timeout: 5))
  }

  func testTandemDraftClearsAllUnsavedFieldsOnBackAndTabExit() {
    for leaveByTab in [false, true] {
      let app = launchScreenshotFixture()
      navigate(to: "Settings", in: app)
      tapNavigationLink("Tandem Account", in: app)
      app.buttons["Change Account Details"].tap()
      let username = app.textFields["Tandem username"]
      let password = app.secureTextFields["Tandem password"]
      let region = app.buttons["TandemRegionPicker"]
      let savedUsername = username.value as? String
      let savedRegion = "\(region.label)|\(region.value as? String ?? "")"
      replaceText(in: username, with: "unsaved@pumpsync.example", app: app)
      password.tap()
      password.typeText("unsaved-password\n")
      region.tap()
      app.buttons["Europe"].firstMatch.tap()
      XCTAssertTrue("\(region.label)|\(region.value as? String ?? "")".contains("Europe"))
      XCTAssertFalse(app.buttons["Cancel"].exists)

      if leaveByTab {
        navigate(to: "Sync", in: app)
        XCTAssertTrue(app.navigationBars["Sync"].waitForExistence(timeout: 5))
        reopenTandemAfterDiscardingPassword(using: app.buttons["Settings"].firstMatch, in: app)
      } else {
        tapBack(in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Tandem"].waitForNonExistence(timeout: 5))
        reopenTandemAfterDiscardingPassword(using: app.buttons["TandemAccountLink"], in: app)
      }
      XCTAssertTrue(app.staticTexts["Saved Account"].waitForExistence(timeout: 5))
      XCTAssertFalse(password.exists)
      app.buttons["Change Account Details"].tap()
      XCTAssertEqual(username.value as? String, savedUsername)
      assertEmptyField(password)
      XCTAssertEqual("\(region.label)|\(region.value as? String ?? "")", savedRegion)
      revealFormControl(app.buttons["Save Changes"], in: app)
      XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
      app.terminate()
    }
  }

  func testFirstTimeTandemDraftIsDiscardedOnBack() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Tandem Account", in: app)
    revealFormControl(app.buttons["Remove Account"], in: app)
    app.buttons["Remove Account"].tap()
    let sheetAction = app.sheets.buttons["Remove Account"].firstMatch
    let popoverAction = app.popovers.buttons["Remove Account"].firstMatch
    XCTAssertTrue(sheetAction.waitForExistence(timeout: 3) || popoverAction.waitForExistence(timeout: 3))
    let confirmation = sheetAction.exists ? sheetAction : popoverAction
    confirmation.tap()
    let username = app.textFields["Tandem username"]
    XCTAssertTrue(username.waitForExistence(timeout: 5))
    replaceText(in: username, with: "unsaved@pumpsync.example", app: app)
    app.secureTextFields["Tandem password"].tap()
    app.secureTextFields["Tandem password"].typeText("unsaved-password\n")
    app.buttons["TandemRegionPicker"].tap()
    app.buttons["Europe"].firstMatch.tap()
    tapBack(in: app)
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Tandem"].waitForNonExistence(timeout: 5))
    reopenTandemAfterDiscardingPassword(using: app.buttons["TandemAccountLink"], in: app)
    assertEmptyField(username)
    assertEmptyField(app.secureTextFields["Tandem password"])
    let region = app.buttons["TandemRegionPicker"]
    XCTAssertTrue("\(region.label)|\(region.value as? String ?? "")".contains("United States"))
    revealFormControl(app.buttons["Connect Account"], in: app)
    XCTAssertFalse(app.buttons["Connect Account"].isEnabled)
  }

  func testConcentrationChoicesHaveNativeSelectionAndAccessibleTargets() {
    let app = launchScreenshotFixture()
    navigate(to: "Settings", in: app)
    tapNavigationLink("Insulin Concentration", in: app)
    XCTAssertTrue(app.navigationBars["Insulin Concentration"].exists)
    for (title, multiplier) in [("U-100", "1"), ("U-200", "2"), ("U-500", "5")] {
      let choice = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
      XCTAssertTrue(choice.waitForExistence(timeout: 5))
      scrollTo(choice, in: app)
      XCTAssertTrue(meetsMinimumHitTargetDimension(choice.frame.height),
                    "Native choice target must be at least 44 points: \(choice.frame)")
      for verticalOffset in [-21.9, 21.9] {
        let other = app.buttons[title == "U-100" ? "U-200" : "U-100"].firstMatch
        other.tap()
        choice.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
          .withOffset(CGVector(dx: 0, dy: verticalOffset)).tap()
        XCTAssertTrue(choice.isSelected, "The native choice must respond throughout a 44-point vertical target")
        XCTAssertFalse(other.isSelected, "Only one concentration may be selected")
      }
      XCTAssertTrue(app.staticTexts["Apple Health imports use \(multiplier)× the pump-reported insulin amount."].exists,
        "The conversion explanation must describe the selected concentration")
    }
    app.buttons["U-200"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["Apple Health imports use 2× the pump-reported insulin amount."].exists,
                  "The conversion explanation must describe the selected concentration")
    attachScreenshot(named: "concentration-native-inline-selection", from: app)
    XCTAssertTrue(app.buttons["U-100"].exists)
    XCTAssertTrue(app.buttons["U-500"].exists)
    tapNavigationLink("How Insulin Conversion Works", in: app)
    XCTAssertTrue(app.navigationBars["Insulin Conversion"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Current Selection"].exists)
    attachScreenshot(named: "review-insulin-conversion-overview", from: app)
    for (concentration, multiplier) in [("U-100", "1"), ("U-200", "2"), ("U-500", "5")] {
      let factor = app.descendants(matching: .any).matching(NSPredicate(
        format: "label == %@ AND value == %@", concentration, "Multiply by \(multiplier)")).firstMatch
      revealFormControl(factor, in: app)
      XCTAssertTrue(factor.isHittable, "Each conversion factor must be readable and accessible")
    }
    attachScreenshot(named: "review-insulin-conversion-factors", from: app)
    let finalGuidance = app.descendants(matching: .any).matching(NSPredicate(
      format: "label CONTAINS %@", "Confirm your concentration against your insulin prescription")).firstMatch
    revealFormControl(finalGuidance, in: app)
    XCTAssertTrue(finalGuidance.isHittable)
    attachScreenshot(named: "review-insulin-conversion-final-guidance", from: app)
  }

  func testSettingsShowsCompactInsulinConcentrationRow() {
    let app = launchScreenshotFixture()

    navigate(to: "Settings", in: app)

    XCTAssertTrue(app.staticTexts["Insulin Concentration"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Apple Health records 1x pump units"].exists)
  }

  func testSyncSettingsAndDeveloperRenderInScreenshotMode() {
    // Actual system text sizes are covered by the native typography gate.
    let app = launchScreenshotFixture()

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))

    navigate(to: "Sync", in: app)
    XCTAssertTrue(app.staticTexts["SyncProgressTitle"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Sync Now"].waitForExistence(timeout: 5))

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.buttons["TandemAccountLink"].waitForExistence(timeout: 5))

    tapNavigationLink("Support & Diagnostics", in: app)
    let share = app.buttons["Share Support Bundle"]
    scrollTo(share, in: app)
    XCTAssertTrue(share.waitForExistence(timeout: 5))
    XCTAssertTrue(share.isHittable)
  }

  func testDesignReviewAdaptiveReachability() {
    let app = launchScreenshotFixture()
    func reveal(_ element: XCUIElement) {
      revealFormControl(element, in: app)
    }
    reveal(app.buttons["Sync Now"])
    XCTAssertGreaterThanOrEqual(app.buttons["Sync Now"].frame.height, 44 - 0.01)
    navigate(to: "Settings", in: app)
    tapNavigationLink("Tandem Account", in: app)
    reveal(app.buttons["Remove Account"])
    for _ in 0..<8 { if app.buttons["Change Account Details"].isHittable { break }; app.swipeDown() }
    app.buttons["Change Account Details"].tap()
    reveal(app.buttons["Save Changes"])
    XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
    tapBack(in: app)
    tapNavigationLink("Insulin Concentration", in: app)
    reveal(app.buttons["How Insulin Conversion Works"])
    tapBack(in: app)
    tapNavigationLink("Data Handling", in: app)
    reveal(app.descendants(matching: .any)["Privacy and Deletion Details"].firstMatch)
    attachScreenshot(named: "design-review-data-handling-final-content", from: app)
    tapBack(in: app)
    tapNavigationLink("Support & Diagnostics", in: app)
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
    func auditUnobscuredContent(screen: String) throws {
      do {
      // Native Form/Label nodes on iOS 27 can report unsupported scaling or
      // predicted clipping even when every word grows and remains reachable.
      // The required standard/max-system-size typography test measures that
      // behavior directly; keep contrast, hit targets and semantics audited here.
      try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription]) { issue in
        // Native floating navigation intentionally blends the scrolled content
        // beneath its pill. Audit that text after revealing it, not while it is
        // physically covered by navigation. Never suppress hit/label issues.
        guard issue.auditType == .contrast else {
          let element = issue.element
          let diagnostic = "CORE_SCREEN_AUDIT screen=\(screen) type=\(issue.auditType) "
            + "description=\(issue.detailedDescription) element=\(String(describing: element))"
          print(diagnostic)
          let evidence = XCTAttachment(string: diagnostic + "\n\n" + app.debugDescription)
          evidence.name = "core-screen-audit-failure-" + screen
          evidence.lifetime = .keepAlways
          self.add(evidence)
          self.attachScreenshot(named: "core-screen-audit-failure-" + screen, from: app)
          if let element, element.exists {
            let details = "label=\(element.label) identifier=\(element.identifier) frame=\(element.frame)"
            print("CORE_SCREEN_AUDIT_ELEMENT: \(details)")
            let target = XCTAttachment(string: details)
            target.name = "core-screen-audit-element-" + screen
            target.lifetime = .keepAlways
            self.add(target)
          }
          return false
        }
        guard let element = issue.element else {
          unresolvedNativeContrastNodes += 1
          print("UNRESOLVABLE_NATIVE_CONTRAST_NODE: \(issue.detailedDescription)")
          self.attachScreenshot(named: "unresolved-native-contrast-\(unresolvedNativeContrastNodes)", from: app)
          return true
        }
        // XCTest can report either the glass button or its label. Measure the
        // centered text against the button background on both phone and tablet.
        if screen == "Sync", element.exists, element.label == "Sync Now" {
          let action = app.buttons["SyncNowButton"]
          guard action.isHittable, app.frame.contains(action.frame) else { return false }
          let textInsideButton = element.elementType == .staticText
            && action.frame.insetBy(dx: -0.5, dy: -0.5).contains(element.frame)
          let identifiedButton = element.elementType == .button && element.identifier == "SyncNowButton"
          print("PRIMARY_ACTION_CONTRAST: type=\(element.elementType) labelFrame=\(element.frame) buttonFrame=\(action.frame)")
          guard textInsideButton || identifiedButton,
                let ratio = self.renderedTextContrast(action, centeredButtonTitle: true), ratio >= 4.5 else { return false }
          print("RENDERED_CONTRAST_VERIFIED: \(element.label) · ratio=\(ratio)")
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
        // Retain the conservative 7:1 check for other native text.
        if element.elementType == .staticText, let ratio = self.renderedTextContrast(element), ratio >= 7 {
          print("RENDERED_CONTRAST_VERIFIED: \(element.label) · ratio=\(ratio)")
          return true
        }
        print("ACCESSIBILITY_AUDIT: \(issue.compactDescription) · \(element.label) · \(element.frame)")
        return false
      }
      } catch { XCTFail("Accessibility audit failed on \(screen): \(error)") }
    }
    func restartAtSettings() {
      // Audits returned the same unresolvable AX identity on six destinations
      // after auditing a scrolled parent in one process.
      // Give each screen an independent audit process, without filtering
      // hit-region or description failures from the resulting audit.
      app.terminate()
      app.launch()
      XCTAssertTrue(app.navigationBars["Sync"].waitForExistence(timeout: 5))
      navigate(to: "Settings", in: app)
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
    try auditUnobscuredContent(screen: "Sync")
    restartAtSettings()
    try auditUnobscuredContent(screen: "Settings-top")
    app.swipeUp()
    try auditUnobscuredContent(screen: "Settings-scrolled")
    for title in ["Tandem Account", "Apple Health", "Insulin Concentration", "Data Handling", "About PumpSync", "Support & Diagnostics"] {
      restartAtSettings()
      tapNavigationLink(title, in: app)
      let navigationTitle = title == "Tandem Account" ? "Tandem" : title
      XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 5))
      attachScreenshot(named: "accessibility-audit-" + title, from: app)
      try auditUnobscuredContent(screen: title + "-top")
      app.swipeUp()
      try auditUnobscuredContent(screen: title + "-scrolled")
      tapBack(in: app)
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
  }

  func testDarkModeCoreScreensRenderInScreenshotMode() {
    let app = launchScreenshotFixture(launchArguments: ["-AppleInterfaceStyle", "Dark"])

    XCTAssertTrue(app.staticTexts["Sync"].waitForExistence(timeout: 5))
    attachScreenshot(named: "appearance-sync", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.buttons["TandemAccountLink"].waitForExistence(timeout: 5))
    attachScreenshot(named: "appearance-settings", from: app)

    tapNavigationLink("Apple Health", in: app)
    XCTAssertTrue(app.staticTexts["Write Permissions"].waitForExistence(timeout: 5))
    attachScreenshot(named: "appearance-health", from: app)
  }

  func testIPadAppStoreScreenshots() {
    let initialApp = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    XCTAssertTrue(initialApp.buttons["Sync Past 14 Days"].waitForExistence(timeout: 5))
    let list = initialApp.collectionViews.containing(.button, identifier: "SyncNowButton").firstMatch
    if list.exists, list.frame.width >= 900, UIApplication.shared.preferredContentSizeCategory == .large {
      let action = initialApp.buttons["SyncNowButton"].frame
      XCTAssertLessThan(action.width, list.frame.width * 0.85, "Wide windows should keep a readable form width")
      XCTAssertEqual(action.midX, list.frame.midX, accuracy: 2)
    }
    attachScreenshot(named: "ipad-pro-13-app-store-listing-01-status-overview.png", from: initialApp)
    initialApp.terminate()

    let app = launchScreenshotFixture()
    XCTAssertTrue(app.staticTexts["SyncProgressTitle"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-02-sync-workflow.png", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.buttons["TandemAccountLink"].waitForExistence(timeout: 5))
    attachScreenshot(named: "ipad-pro-13-app-store-listing-03-settings-pumpsync.png", from: app)

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
    tapNavigationLink("Support & Diagnostics", in: app)
    revealDeveloperDiagnosticsSection(in: app)
    attachScreenshot(named: "ipad-pro-13-app-store-listing-09-developer.png", from: app)
  }

  func testIPhoneAppStoreScreenshots() {
    let initialApp = launchScreenshotFixture(launchArguments: ["--pumpsync-screenshot-initial-sync"])
    XCTAssertTrue(initialApp.buttons["Sync Past 14 Days"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-01-status-overview.png", from: initialApp)
    initialApp.terminate()

    let app = launchScreenshotFixture()
    XCTAssertTrue(app.staticTexts["SyncProgressTitle"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-02-sync-workflow.png", from: app)

    navigate(to: "Settings", in: app)
    XCTAssertTrue(app.buttons["TandemAccountLink"].waitForExistence(timeout: 5))
    attachScreenshot(named: "iphone-6-7-app-store-listing-03-settings-pumpsync.png", from: app)

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

    tapNavigationLink("Support & Diagnostics", in: app)
    revealDeveloperDiagnosticsSection(in: app)
    attachScreenshot(named: "iphone-6-7-app-store-listing-09-developer.png", from: app)
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
    revealFormControl(history, in: app)
    XCTAssertTrue(history.waitForExistence(timeout: 5))
    XCTAssertTrue(history.isHittable)
    history.tap()
    XCTAssertTrue(app.buttons["Past 2 days"].waitForExistence(timeout: 5))
    attachScreenshot(named: "remediation-history-menu-light", from: app)
    app.buttons["Past 14 days"].firstMatch.tap()
    navigate(to: "Settings", in: app)
    attachScreenshot(named: "remediation-settings-light", from: app)
    tapNavigationLink("Tandem Account", in: app)
    let sourceHeader = app.staticTexts["Saved Account"]
    XCTAssertTrue(sourceHeader.waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Tandem"].exists)
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
    for title in ["U-100", "U-200", "U-500"] {
      XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 5))
    }
    app.buttons["U-200"].firstMatch.tap()
    XCTAssertTrue(app.buttons["U-200"].firstMatch.isSelected)
    attachScreenshot(named: "remediation-concentration-inline-light", from: app)
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
    tapNavigationLink("Support & Diagnostics", in: app)
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

  private func reopenTandemAfterDiscardingPassword(using control: XCUIElement, in app: XCUIApplication) {
    // AutoFill can present its sheet after Back has already exposed Settings.
    // Watch the sheet and the real navigation target until Tandem is visible.
    let sheet = app.sheets["Save Password?"].firstMatch
    let destination = app.navigationBars["Tandem"]
    let deadline = Date.now.addingTimeInterval(30)
    while Date.now < deadline {
      if sheet.exists {
        let decline = sheet.buttons["Not Now"].firstMatch
        guard decline.wait(for: \.isHittable, toEqual: true, timeout: 5) else {
          XCTFail("The AutoFill sheet must allow declining the synthetic password")
          return
        }
        decline.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
      } else if destination.exists && destination.isHittable {
        return
      } else if control.exists && control.isHittable {
        control.tap()
      } else {
        RunLoop.current.run(until: Date.now.addingTimeInterval(0.2))
      }
    }
    recordUIState(named: "could-not-reopen-tandem", in: app)
    XCTFail("The Tandem account screen must reopen after discarding a credential draft")
  }

  private func dismissLogActions(in app: XCUIApplication) {
    // An untargeted tap on iPad can land inside the anchored menu.
    let copy = app.buttons["CopyDiagnosticsLog"]
    XCTAssertTrue(copy.exists)
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)).tap()
    XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
  }

  private func tapBack(in app: XCUIApplication) {
    // Some installed runtimes expose native Back as Other in legacy AX data.
    // Its observed system identifier remains stable across those role changes.
    let back = app.navigationBars.descendants(matching: .any).matching(identifier: "BackButton").firstMatch
    if back.exists { back.tap() }
    else { app.navigationBars.buttons.firstMatch.tap() }
  }

  private func dismissSyncMessage(in app: XCUIApplication) {
    let dismiss = app.buttons["DismissSyncMessageButton"]
    XCTAssertTrue(dismiss.wait(for: \.isHittable, toEqual: true, timeout: 5))
    dismiss.tap()
    XCTAssertTrue(dismiss.waitForNonExistence(timeout: 5))
  }

  private func replaceText(in field: XCUIElement, with text: String, app: XCUIApplication) {
    revealFormControl(field, in: app)
    field.tap()
    for surface in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
      let tip = surface.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "sliding your finger across the letters")).firstMatch
      if tip.exists, surface.buttons["Continue"].exists { surface.buttons["Continue"].tap() }
    }
    let existing = field.value as? String ?? ""
    if existing != field.placeholderValue {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
    }
    field.typeText(text)
  }

  private func assertEmptyField(_ field: XCUIElement) {
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    let value = field.value as? String ?? ""
    XCTAssertTrue(value.isEmpty || value == field.placeholderValue,
                  "An abandoned edit must reload the empty saved field: \(field.identifier)")
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
      "Insulin Concentration": "InsulinConcentrationLink",
      "About PumpSync": "AboutPumpSyncLink",
      "Data Handling": "DataHandlingLink",
      "Support & Diagnostics": "DeveloperLink"
    ][title]

    if let identifier {
      let identifiedLink = app.buttons[identifier]
      if identifiedLink.waitForExistence(timeout: 2) {
        revealFormControl(identifiedLink, in: app)
        XCTAssertTrue(identifiedLink.isHittable, "Navigation link must be reachable: \(title)")
        identifiedLink.tap()
        return
      }
    }

    let link = app.buttons[title]
    if link.waitForExistence(timeout: 2) {
      scrollTo(link, in: app)
      link.tap()
      return
    }

    let cell = app.cells.containing(.staticText, identifier: title).firstMatch
    scrollTo(cell, in: app)
    XCTAssertTrue(cell.waitForExistence(timeout: 5), "Could not find navigation link \(title)")
    cell.tap()
  }

  private func assertDeveloperDiagnosticsVisible(in app: XCUIApplication) {
    revealDeveloperDiagnosticsSection(in: app)
    for (identifier, title) in [
      ("appEventsLogLink", "App Event Log"),
      ("devicePerformanceLogLink", "Device Performance Diagnostics")
    ] {
      let link = app.buttons[identifier]
      scrollTo(link, in: app)
      XCTAssertTrue(link.waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts[title].exists)
      XCTAssertTrue(link.isHittable)
    }
    let share = app.buttons["Share Support Bundle"]
    scrollTo(share, in: app)
    XCTAssertTrue(share.waitForExistence(timeout: 5))
    XCTAssertTrue(share.isHittable)
  }

  private func revealDeveloperDiagnosticsSection(in app: XCUIApplication) {
    let header = app.staticTexts["Diagnostics"]
    scrollTo(header, in: app)
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    XCTAssertTrue(header.isHittable)
  }

  private func revealFormControl(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<48 {
      let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
        : app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app
      var offset = -0.25
      if element.exists {
        let tabBar = app.tabBars.firstMatch
        let isBehindBottomTabBar = tabBar.exists && tabBar.frame.midY > app.frame.midY
          && element.frame.midY >= tabBar.frame.minY - 8
        if element.isHittable && !isBehindBottomTabBar { return }
        let distanceToCenter = element.frame.midY - app.frame.midY
        let distance = min(0.4, max(0.08, abs(distanceToCenter) / max(1, scroll.frame.height)))
        offset = distanceToCenter < 0 ? distance : -distance
      }
      // Native rows may not exist until they approach the viewport. Small,
      // slow drags reveal them without full-swipe momentum skipping the target.
      let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      let finish = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + offset))
      start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    recordUIState(named: "unreachable-form-control", in: app)
    XCTFail("Form control must be reachable: \(element)")
  }

  private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<24 {
      let tabBar = app.tabBars.firstMatch
      let isBehindBottomTabBar = element.exists && tabBar.exists && tabBar.frame.midY > app.frame.midY
        && element.frame.midY >= tabBar.frame.minY - 8
      if element.isHittable && !isBehindBottomTabBar { return }
      let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
      guard scroll.exists else { return }
      if element.exists && element.frame.midY < scroll.frame.midY { scroll.swipeDown() }
      else { scroll.swipeUp() }
    }
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

@MainActor
extension XCTestCase {
  func renderedTextContrast(_ element: XCUIElement, centeredButtonTitle: Bool = false) -> Double? {
    guard var image = element.screenshot().image.cgImage else { return nil }
    if centeredButtonTitle {
      // Exclude capsule edges and the underlying Form. The center contains
      // only the single text title and the surface it actually appears on.
      let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
      guard let titleArea = image.cropping(to: rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.2)) else { return nil }
      image = titleArea
    }
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
}
