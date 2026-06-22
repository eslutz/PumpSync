import XCTest
@testable import PumpSync

final class HostedSubscriptionPresentationTests: XCTestCase {
  func testDismissesAfterManageSubscriptionWhenConnectionIsRestored() {
    XCTAssertTrue(HostedSubscriptionPresentation.shouldDismissAfterManageSubscriptions(isSignedIn: true))
  }

  func testKeepsSheetAfterManageSubscriptionWhenConnectionIsStillMissing() {
    XCTAssertFalse(HostedSubscriptionPresentation.shouldDismissAfterManageSubscriptions(isSignedIn: false))
  }
}
