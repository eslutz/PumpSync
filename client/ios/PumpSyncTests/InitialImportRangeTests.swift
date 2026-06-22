import XCTest
@testable import PumpSync

final class InitialImportRangeTests: XCTestCase {
  func testMinimumDateUsesSelectedRangeForInitialSync() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = ISO8601DateFormatter().date(from: "2026-06-22T12:34:56Z")!

    XCTAssertEqual(InitialImportRange.startFromNow.minimumDate(relativeTo: now, calendar: calendar), now)
    XCTAssertEqual(InitialImportRange.pastTwoDays.minimumDate(relativeTo: now, calendar: calendar), ISO8601DateFormatter().date(from: "2026-06-20T00:00:00Z"))
    XCTAssertEqual(InitialImportRange.pastWeek.minimumDate(relativeTo: now, calendar: calendar), ISO8601DateFormatter().date(from: "2026-06-15T00:00:00Z"))
    XCTAssertEqual(InitialImportRange.pastTwoWeeks.minimumDate(relativeTo: now, calendar: calendar), ISO8601DateFormatter().date(from: "2026-06-08T00:00:00Z"))
  }

  func testDefaultInitialImportRangeIsPastWeek() {
    XCTAssertEqual(InitialImportRange.default, .pastWeek)
  }
}
