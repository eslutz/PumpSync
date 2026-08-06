import XCTest
@testable import PumpSync

final class SubscriptionPresentationTests: XCTestCase {
  func testDismissesAfterManageSubscriptionWhenConnectionIsRestored() {
    XCTAssertTrue(SubscriptionPresentation.shouldDismissAfterManageSubscriptions(isSignedIn: true))
  }

  func testKeepsSheetAfterManageSubscriptionWhenConnectionIsStillMissing() {
    XCTAssertFalse(SubscriptionPresentation.shouldDismissAfterManageSubscriptions(isSignedIn: false))
  }
}
