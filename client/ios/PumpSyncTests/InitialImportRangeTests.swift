import XCTest
@testable import PumpSync

final class InitialImportRangeTests: XCTestCase {
  func testMinimumDateUsesSelectedRangeForInitialSync() {
    let now = Date(timeIntervalSince1970: 1_800_000)

    XCTAssertEqual(InitialImportRange.startFromNow.minimumDate(relativeTo: now), now)
    XCTAssertEqual(InitialImportRange.pastTwoDays.minimumDate(relativeTo: now), now.addingTimeInterval(-2 * 24 * 60 * 60))
    XCTAssertEqual(InitialImportRange.pastWeek.minimumDate(relativeTo: now), now.addingTimeInterval(-7 * 24 * 60 * 60))
    XCTAssertEqual(InitialImportRange.pastTwoWeeks.minimumDate(relativeTo: now), now.addingTimeInterval(-(14 * 24 * 60 * 60 - 10 * 60)))
  }

  func testDefaultInitialImportRangeIsPastWeek() {
    XCTAssertEqual(InitialImportRange.default, .pastWeek)
  }
}
