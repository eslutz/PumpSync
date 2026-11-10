import XCTest
import UIKit

@MainActor
final class NativeRefactorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSyncProgressPrecedesActionAndCountsRemainOrderedWithConcentrationInSettings() {
        let app = fixture()
        let received = app.staticTexts["SyncRecordsReceived"]
        let saved = app.staticTexts["SyncSamplesSaved"]
        XCTAssertTrue(received.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sync Now"].waitForExistence(timeout: 5))
        XCTAssertLessThan(received.frame.minY, saved.frame.minY)
        let progress = app.staticTexts["SyncProgressTitle"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertLessThan(progress.frame.minY, app.buttons["Sync Now"].frame.minY)
        XCTAssertLessThan(app.buttons["Sync Now"].frame.minY, received.frame.minY)
        XCTAssertFalse(app.staticTexts["Insulin Concentration"].exists)
        capture("native-sync", app: app)
        settings(app)
        open("InsulinConcentrationLink", app: app)
        XCTAssertTrue(app.navigationBars["Insulin Concentration"].waitForExistence(timeout: 3))
    }

    func testSubscriptionHasOneSettingsEntryAndDiscoverableRestore() {
        let app = fixture()
        settings(app)
        XCTAssertEqual(app.buttons.matching(identifier: "SubscriptionSettingsLink").count, 1)
        XCTAssertFalse(app.buttons["RestorePurchasesButton"].exists)
        capture("native-settings", app: app)
        open("SubscriptionSettingsLink", app: app)
        XCTAssertTrue(app.buttons["ManageSubscriptionButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RestorePurchasesButton"].exists)
        capture("native-subscription", app: app)
    }

    func testPerformanceShowsStructuredMeasurementsAndOptionalReportData() {
        let app = fixture()
        developer(app)
        open("devicePerformanceLogLink", app: app)
        open("Performance metrics", app: app)
        XCTAssertTrue(app.staticTexts["Measurements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CPU time"].exists)
        let cpu = app.staticTexts["PerformanceMeasurement-CPU time"]
        XCTAssertTrue(cpu.waitForExistence(timeout: 5))
        XCTAssertEqual(cpu.label, "CPU time, 1 sec")
        XCTAssertTrue(app.staticTexts["From"].exists)
        assertDiagnosticExportActions(app)
        XCTAssertFalse(app.staticTexts["DiagnosticRecordDetail"].exists)
        capture("native-performance", app: app)
        open("Report Data", app: app)
        XCTAssertTrue(app.staticTexts["DiagnosticRecordDetail"].waitForExistence(timeout: 3))
    }

    func testEventsGroupStagesWithoutLosingTheirTimeline() {
        let app = fixture()
        developer(app)
        open("appEventsLogLink", app: app)
        XCTAssertTrue(app.staticTexts["Manual sync completed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Manual sync completed").count, 1)
        XCTAssertFalse(app.staticTexts["Manual sync recovering"].exists)
        capture("native-events", app: app)
        open("Manual sync completed", app: app)
        XCTAssertTrue(app.staticTexts["Records received"].waitForExistence(timeout: 5))
        open("Recorded Stages", app: app)
        XCTAssertTrue(app.staticTexts["Manual sync recovering"].waitForExistence(timeout: 3))
        capture("native-event-timeline", app: app)
    }

    func testNativeTypographyAndFinalContentFollowSystemTextSize() {
        // The validation script changes the actual simulator setting before
        // starting this process. Do not inject a SwiftUI or launch-font override.
        let category = UIApplication.shared.preferredContentSizeCategory
        let bodyLineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let standardBodyLineHeight = UIFont.preferredFont(forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).lineHeight
        let environment = "NATIVE_TYPOGRAPHY category=\(category.rawValue) bodyLineHeight=\(bodyLineHeight) standardBodyLineHeight=\(standardBodyLineHeight)"
        print(environment)
        attachText(environment, named: "native-system-typography")

        let app = fixture()
        let saved = app.staticTexts.matching(NSPredicate(format: "label == %@", "Samples saved")).firstMatch
        revealEnd(of: saved, in: app, minimumVisibleHeight: bodyLineHeight)
        XCTAssertEqual(saved.label, "Samples saved")
        // Measure the label itself, not the combined label/value row. A fixed
        // standard-size label cannot satisfy the accessibility-size minimum.
        XCTAssertGreaterThanOrEqual(saved.frame.height, bodyLineHeight * 0.85)
        if category.isAccessibilityCategory {
            XCTAssertGreaterThan(bodyLineHeight, standardBodyLineHeight)
            XCTAssertGreaterThan(saved.frame.height, standardBodyLineHeight * 1.5)
        }
        let measurement = "NATIVE_TYPOGRAPHY samplesSavedHeight=\(saved.frame.height) category=\(category.rawValue)"
        print(measurement)
        attachText(measurement, named: "native-samples-saved-size")
        capture("native-typography-sync", app: app)

        settings(app)
        // Follow the Settings row order. At maximum text size, revealing a
        // later row can recycle earlier rows out of the accessibility tree.
        open("TandemAccountLink", app: app)
        assertReadableText("Saved on this device", app: app, bodyLineHeight: bodyLineHeight,
            evidenceName: "native-typography-tandem-password")
        let edit = app.buttons["Change Account Details"].firstMatch
        revealEnd(of: edit, in: app, minimumVisibleHeight: bodyLineHeight)
        XCTAssertEqual(edit.label, "Change Account Details")
        XCTAssertTrue(edit.isEnabled)
        XCTAssertTrue(edit.isHittable)
        capture("native-typography-tandem-edit", app: app)
        edit.tap()
        XCTAssertTrue(app.secureTextFields["Tandem password"].waitForExistence(timeout: 5))
        assertReadableText("Enter the password you currently use for Tandem. This updates the login saved in PumpSync; it does not change your Tandem password.",
            app: app, bodyLineHeight: bodyLineHeight, evidenceName: "native-typography-tandem-instructions")
        back(app)

        open("AppleHealthLink", app: app)
        assertReadableText("PumpSync writes insulin delivery and carbohydrate samples to Apple Health. It does not read other Health data.",
            app: app, bodyLineHeight: bodyLineHeight, evidenceName: "native-typography-health-explanation")
        back(app)
        assertReadableText("U-100", app: app, bodyLineHeight: bodyLineHeight,
            evidenceName: "native-typography-settings-concentration")
        open("AboutPumpSyncLink", app: app)
        assertReadableText("Shows the last completed sync, even when there were no new records.",
            app: app, bodyLineHeight: bodyLineHeight, evidenceName: "native-typography-about-final-paragraph")
    }

    func testAccessibilityAuditsSubscriptionAndPerformance() {
        let app = fixture()
        settings(app)
        open("SubscriptionSettingsLink", app: app)
        XCTAssertTrue(app.buttons["ManageSubscriptionButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["RestorePurchasesButton"].exists)
        capture("native-subscription-accessibility", app: app)
        audit(app, screen: "Subscription")

        // Keep the audit diagnostics independent between destinations.
        app.terminate()
        app.launch()
        settings(app)
        open("DeveloperLink", app: app)
        open("devicePerformanceLogLink", app: app)
        open("Performance metrics", app: app)
        let cpu = app.staticTexts["PerformanceMeasurement-CPU time"]
        XCTAssertTrue(cpu.waitForExistence(timeout: 5))
        XCTAssertEqual(cpu.label, "CPU time, 1 sec")
        assertDiagnosticExportActions(app)
        capture("native-performance-accessibility", app: app)
        audit(app, screen: "Performance")
    }

    private func audit(_ app: XCUIApplication, screen: String) {
        // Keep all five audit types. The one measured iOS 26.5 promoted-header
        // false positive below must still pass a conservative pixel check.
        continueAfterFailure = true
        defer { continueAfterFailure = false }
        do {
            let auditTypes: [XCUIAccessibilityAuditType] = [.contrast,
                [.hitRegion, .textClipped, .dynamicType, .sufficientElementDescription]]
            for types in auditTypes {
                try app.performAccessibilityAudit(for: types) { issue in
                    let element = issue.element
                    let evidence = "NATIVE_DETAIL_AUDIT screen=\(screen) type=\(issue.auditType) "
                        + "description=\(issue.detailedDescription) element=\(String(describing: element))"
                    print(evidence)
                    self.attachText(evidence, named: "native-detail-audit-\(screen)")
                    if let element, element.exists {
                        self.attachText("label=\(element.label) identifier=\(element.identifier) frame=\(element.frame)",
                            named: "native-detail-audit-element-\(screen)")
                    }
                    self.attachText(app.debugDescription, named: "native-detail-audit-hierarchy-\(screen)")
                    let version = ProcessInfo.processInfo.operatingSystemVersion
                    if version.majorVersion == 26, version.minorVersion == 5,
                        screen == "Performance", issue.auditType == .contrast,
                        let element, element.exists, element.elementType == .staticText,
                        element.label == "Performance metrics",
                        app.navigationBars.firstMatch.exists, app.tabBars.firstMatch.exists {
                        let frame = element.frame
                        let appFrame = app.frame
                        let navigationFrame = app.navigationBars.firstMatch.frame
                        let tabFrame = app.tabBars.firstMatch.frame
                        // Native edges can differ by floating-point rounding
                        // (observed 4.3e-14 pt), far below one rendered pixel.
                        let belowNavigation = frame.minY >= navigationFrame.maxY - 1e-6
                        let geometry = "HEADER_GEOMETRY header=\(frame) app=\(appFrame) nav=\(navigationFrame) tab=\(tabFrame) "
                            + "headerTop=\(String(format: "%.17g", Double(frame.minY))) "
                            + "navBottom=\(String(format: "%.17g", Double(navigationFrame.maxY))) "
                            + "contained=\(appFrame.contains(frame)) belowNavigation=\(belowNavigation) aboveTabs=\(frame.maxY < tabFrame.minY)"
                        print(geometry)
                        self.attachText(geometry, named: "native-performance-header-geometry")
                        guard appFrame.contains(frame), belowNavigation,
                            frame.maxY < tabFrame.minY,
                            let ratio = self.renderedTextContrast(element), ratio >= 7 else { return false }
                        // Original sRGB glyph interiors independently measure
                        // 18.819:1. Do not accept nil/other nodes or covered text.
                        self.attachText("RENDERED_HEADER_CONTRAST_VERIFIED ratio=\(ratio) frame=\(frame)",
                            named: "native-performance-header-contrast")
                        let attachment = XCTAttachment(screenshot: element.screenshot())
                        attachment.name = "native-performance-header-rendered"
                        attachment.lifetime = .keepAlways
                        self.add(attachment)
                        return true
                    }
                    return false
                }
            }
        } catch {
            XCTFail("\(screen) accessibility audit failed: \(error)")
        }
    }

    private func fixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--pumpsync-screenshot-mode", "--pumpsync-screenshot-diagnostics"]
        app.launchEnvironment["PUMPSYNC_SCREENSHOT_MODE"] = "1"
        app.launch()
        return app
    }

    private func settings(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Settings"]
        if tab.exists { tab.tap() } else { app.buttons["Settings"].firstMatch.tap() }
    }

    private func developer(_ app: XCUIApplication) {
        settings(app)
        open("DeveloperLink", app: app)
    }

    private func assertDiagnosticExportActions(_ app: XCUIApplication) {
        let copy = app.buttons["CopyDiagnosticEntry"]
        var openedOverflow = false
        if !copy.isHittable {
            let fallback = app.buttons["DiagnosticExportActions"]
            let nativeOverflow = app.navigationBars.buttons["More"].firstMatch
            let overflow = fallback.exists ? fallback : nativeOverflow
            if !overflow.waitForExistence(timeout: 3) {
                attachText(app.debugDescription, named: "diagnostic-toolbar-hierarchy")
            }
            XCTAssertTrue(overflow.isHittable, "Native toolbar export actions must remain reachable")
            overflow.tap()
            openedOverflow = true
        }
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(app.buttons["Share Entry"].exists)
        if openedOverflow { app.tap() }
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.matching(identifier: "BackButton").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    private func assertReadableText(_ text: String, app: XCUIApplication,
        bodyLineHeight: CGFloat, evidenceName: String) {
        let element = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        revealEnd(of: element, in: app, minimumVisibleHeight: bodyLineHeight)
        XCTAssertEqual(element.label, text)
        XCTAssertGreaterThanOrEqual(element.frame.height, bodyLineHeight * 0.85)
        attachText("\(text)\nFrame: \(element.frame)", named: evidenceName + "-text")
        capture(evidenceName, app: app)
    }

    private func revealEnd(of element: XCUIElement, in app: XCUIApplication, minimumVisibleHeight: CGFloat) {
        // A paragraph can be taller than a compact screen at maximum text size.
        // Verify its final line is reachable rather than requiring the entire
        // paragraph to fit onscreen or treating native wrapping as clipping.
        for _ in 0..<20 {
            let navigationBar = app.navigationBars.firstMatch
            let tabBar = app.tabBars.firstMatch
            let top = navigationBar.exists ? navigationBar.frame.maxY : app.frame.minY
            // Native Form footers can end exactly at the tab bar's edge.
            // Their text frame remains unobscured there; an extra margin
            // would incorrectly reject the final line at the scroll limit.
            let bottom = tabBar.exists && tabBar.frame.midY > app.frame.midY
                ? tabBar.frame.minY : app.frame.maxY - 8
            if element.exists {
                let frame = element.frame
                let finalLineHeight = min(minimumVisibleHeight, frame.height)
                if frame.width > 0, frame.height > 0, frame.maxY <= bottom,
                    frame.maxY - finalLineHeight >= top,
                    frame.minX >= app.frame.minX, frame.maxX <= app.frame.maxX {
                    print("NATIVE_TEXT_VISIBILITY frame=\(frame) top=\(top) bottom=\(bottom) finalLineHeight=\(finalLineHeight)")
                    return
                }
                // A long paragraph's center can remain outside the viewport
                // even when its final line is visible. Use line geometry here;
                // interactive controls are separately required to be hittable.
                let desiredEndY = bottom - finalLineHeight * 0.5
                let distanceToEnd = frame.maxY - desiredEndY
                let identity = element.identifier.isEmpty ? element.label : element.identifier
                // The identifier overload rejects long paragraph labels.
                let descendant = NSPredicate(format: "identifier == %@ OR label == %@", identity, identity)
                let containingScroll = app.scrollViews.containing(descendant).firstMatch
                let containingList = app.collectionViews.containing(descendant).firstMatch
                let scroll = containingList.exists ? containingList
                    : containingScroll.exists ? containingScroll
                    : app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
                    : app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app
                let distance = min(0.4, max(0.08, abs(distanceToEnd) / max(1, scroll.frame.height)))
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let finish = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5,
                    dy: 0.5 + (distanceToEnd < 0 ? distance : -distance)))
                start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
            } else {
                app.swipeUp()
            }
        }
        attachText(app.debugDescription, named: "unreachable-final-line-hierarchy")
        capture("unreachable-final-line", app: app)
        XCTFail("Could not reveal the final line of \(element.label)")
    }

    private func open(_ identifier: String, app: XCUIApplication) {
        for _ in 0..<20 {
            let button = app.buttons[identifier].firstMatch
            let cell = app.cells.containing(.staticText, identifier: identifier).firstMatch
            let target = button.exists ? button : cell
            // Native Form rows can still be exposed beneath the floating tab
            // bar. Bring their center into content before XCTest taps it.
            let tabBar = app.tabBars.firstMatch
            let navigationBar = app.navigationBars.firstMatch
            let top = navigationBar.exists ? navigationBar.frame.maxY : app.frame.minY
            let bottom = tabBar.exists && tabBar.frame.midY > app.frame.midY
                ? tabBar.frame.minY - 8 : app.frame.maxY - 8
            let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
                : app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app
            var distanceToCenter = scroll.frame.height * 0.25
            if target.exists {
                let center = target.frame.midY
                if target.isHittable && center >= top && center < bottom { target.tap(); return }
                distanceToCenter = center - (top + bottom) * 0.5
            }
            // Full swipes can alternate past a tall row at accessibility sizes.
            let distance = min(0.25, max(0.08, abs(distanceToCenter) / max(1, scroll.frame.height)))
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let finish = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5,
                dy: 0.5 + (distanceToCenter < 0 ? distance : -distance)))
            start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        attachText(app.debugDescription, named: "unreachable-navigation-row-hierarchy")
        capture("unreachable-navigation-row", app: app)
        XCTFail("Could not reach \(identifier)")
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachText(_ text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
