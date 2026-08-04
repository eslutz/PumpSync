import XCTest
@testable import PumpSync

final class PolicyURLTests: XCTestCase {
  // These URLs back the paywall's policy destinations, which App Review
  // guideline 3.1.2 requires for the auto-renewable subscription. A typo would
  // ship a broken legal link, so pin the exact published addresses.
  func testTermsOfUseURLMatchesPublishedPage() {
    XCTAssertEqual(AppConstants.termsOfUseURL.absoluteString, "https://pumpsync.ericslutz.dev/terms/")
  }

  func testPrivacyPolicyURLMatchesPublishedPage() {
    XCTAssertEqual(AppConstants.privacyPolicyURL.absoluteString, "https://pumpsync.ericslutz.dev/privacy/")
  }

  func testPolicyURLsUseHTTPS() {
    XCTAssertEqual(AppConstants.termsOfUseURL.scheme, "https")
    XCTAssertEqual(AppConstants.privacyPolicyURL.scheme, "https")
  }
}
