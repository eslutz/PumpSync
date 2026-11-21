import XCTest
@testable import PumpSync

final class PolicyURLTests: XCTestCase {
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
