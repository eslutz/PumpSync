import XCTest

/// Repeatable simulator comparison using synthetic data and no service calls.
/// Device performance and real Health imports are separate acceptance checks.
@MainActor
final class NativePresentationPerformanceTests: XCTestCase {
    func testFixtureLaunchPerformance() {
        let app = fixture()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
        }
        app.terminate()
    }

    func testSettingsScrollingPerformance() {
        let app = fixture()
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app),
                          XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            app.swipeUp()
            app.swipeDown()
        }
        app.terminate()
    }

    private func fixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--pumpsync-screenshot-mode"]
        app.launchEnvironment["PUMPSYNC_SCREENSHOT_MODE"] = "1"
        return app
    }
}
