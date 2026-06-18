import XCTest
@testable import PumpSync

@MainActor
final class AuthServiceTests: XCTestCase {
  func testSignInPublishesAppleAndBackendStagesBeforeSession() async {
    let session = AppleSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 1_800),
      user: UserSummary(userId: "user-1", email: "user@example.com")
    )
    let service = AuthService(
      authorizeWithApple: {
        AppleAuthorizationPayload(
          identityToken: "identity-token",
          authorizationCode: "authorization-code",
          email: "user@example.com",
          fullName: "Test User"
        )
      },
      createAppleSession: { _ in session }
    )

    await service.signIn()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Signed in as user@example.com.")
  }

  func testSignInPublishesBackendError() async {
    let service = AuthService(
      authorizeWithApple: {
        AppleAuthorizationPayload(
          identityToken: "identity-token",
          authorizationCode: nil,
          email: nil,
          fullName: nil
        )
      },
      createAppleSession: { _ in throw APIClientError.httpStatus(401, "Apple identity token validation failed.") }
    )

    await service.signIn()

    XCTAssertFalse(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertEqual(service.statusMessage, "Sign in failed.")
    XCTAssertEqual(service.errorMessage, "Apple identity token validation failed.")
  }
}
