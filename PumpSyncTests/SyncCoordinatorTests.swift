import XCTest
@testable import PumpSync

final class SyncCoordinatorTests: XCTestCase {
  func testSyncWindowClampsStaleSuccessfulSyncToRecentCompleteDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = ISO8601DateFormatter().date(from: "2026-07-14T19:38:39Z")!
    let lastSuccessfulSyncAt = ISO8601DateFormatter().date(from: "2026-06-22T12:20:34Z")!
    let initialImportDate = ISO8601DateFormatter().date(from: "2026-07-07T00:00:00Z")!

    let window = SyncCoordinator.syncWindow(
      lastSuccessfulSyncAt: lastSuccessfulSyncAt,
      initialImportDate: initialImportDate,
      now: now,
      calendar: calendar
    )

    XCTAssertEqual(window.minDate, ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
    XCTAssertEqual(window.maxDate, ISO8601DateFormatter().date(from: "2026-07-13T23:59:59Z"))
    XCTAssertLessThan(window.maxDate.timeIntervalSince(window.minDate), AppConstants.tandemSyncWindowInterval)
  }

  func testSyncWindowUsesLastFullDayWhenInitialImportRequestsMaximumRange() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = ISO8601DateFormatter().date(from: "2026-07-14T19:38:39Z")!
    let initialImportDate = ISO8601DateFormatter().date(from: "2026-06-30T00:00:00Z")!

    let window = SyncCoordinator.syncWindow(
      lastSuccessfulSyncAt: nil,
      initialImportDate: initialImportDate,
      now: now,
      calendar: calendar
    )

    XCTAssertEqual(window.minDate, ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z"))
    XCTAssertEqual(window.maxDate, ISO8601DateFormatter().date(from: "2026-07-13T23:59:59Z"))
    XCTAssertLessThan(window.maxDate.timeIntervalSince(window.minDate), AppConstants.tandemSyncWindowInterval)
  }
}
