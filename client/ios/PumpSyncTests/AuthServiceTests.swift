import XCTest
@testable import PumpSync

@MainActor
final class AuthServiceTests: XCTestCase {
  func testSignInPublishesAppleAndBackendStagesBeforeSession() async {
    let diagnostics = DiagnosticsLogStore()
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
      createAppleSession: { _ in session },
      diagnostics: diagnostics
    )

    await service.signIn()

    XCTAssertTrue(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertNil(service.errorMessage)
    XCTAssertEqual(service.statusMessage, "Signed in as user@example.com.")
    XCTAssertEqual(diagnostics.entries.map(\.title), ["PumpSync session created", "Apple authorization completed", "Sign in started"])
  }

  func testSignInPublishesSafeBackendErrorAndDiagnostics() async {
    let diagnostics = DiagnosticsLogStore()
    let service = AuthService(
      authorizeWithApple: {
        AppleAuthorizationPayload(
          identityToken: "identity-token",
          authorizationCode: nil,
          email: nil,
          fullName: nil
        )
      },
      createAppleSession: { _ in throw APIClientError.httpStatus(401, "Apple identity token validation failed for user@example.com.") },
      diagnostics: diagnostics
    )

    await service.signIn()

    XCTAssertFalse(service.isSignedIn)
    XCTAssertFalse(service.isSigningIn)
    XCTAssertEqual(service.statusMessage, "Sign in could not be completed. Try again.")
    XCTAssertEqual(service.errorMessage, "Sign in could not be completed. Try again.")
    XCTAssertEqual(diagnostics.entries.first?.title, "Sign in failed")
    XCTAssertEqual(diagnostics.entries.first?.message, "Apple identity token validation failed for [redacted email].")
  }
}
