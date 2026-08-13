import XCTest
@testable import PumpSync

final class BackgroundSyncDiagnosticsTests: XCTestCase {
  func testSchedulingContextIncludesBuildRefreshStatusAndLowPowerMode() {
    let context = BackgroundSyncDiagnostics.schedulingContext(
      buildNumber: "4",
      refreshStatus: .available,
      isLowPowerModeEnabled: true
    )

    XCTAssertEqual(context, "build=4 refreshStatus=available lowPowerMode=true")
  }

  func testPendingRequestDescriptionIncludesIdentifierAndEarliestBeginDate() {
    let date = Date(timeIntervalSince1970: 1_786_590_000)

    let description = BackgroundSyncDiagnostics.pendingRequestDescription(
      identifier: "dev.ericslutz.PumpSync.daily-sync",
      earliestBeginDate: date
    )

    XCTAssertEqual(
      description,
      "identifier=dev.ericslutz.PumpSync.daily-sync earliestBeginDate=2026-08-13T03:00:00Z"
    )
  }

  func testPendingRequestDescriptionHandlesMissingEarliestBeginDate() {
    XCTAssertEqual(
      BackgroundSyncDiagnostics.pendingRequestDescription(identifier: "task", earliestBeginDate: nil),
      "identifier=task earliestBeginDate=none"
    )
  }

  func testBackgroundStageIncludesBuildAndElapsedTime() {
    XCTAssertEqual(
      BackgroundSyncDiagnostics.stageDescription(buildNumber: "4", stage: "downloading", elapsedMs: 275),
      "build=4 stage=downloading elapsedMs=275"
    )
  }
}
