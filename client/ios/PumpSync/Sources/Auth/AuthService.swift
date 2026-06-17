import AuthenticationServices
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AuthService {
  private let apiClient: PumpSyncAPIClient
  private let authorizationBroker = AppleAuthorizationBroker()

  private(set) var session: AppleSessionResponse?
  private(set) var isSigningIn = false
  var errorMessage: String?

  init(apiClient: PumpSyncAPIClient) {
    self.apiClient = apiClient
  }

  var isSignedIn: Bool {
    session != nil
  }

  var accessToken: String? {
    session?.accessToken
  }

  func signIn() async {
    isSigningIn = true
    errorMessage = nil

    do {
      let payload = try await authorizationBroker.requestAuthorization()
      let request = AppleSessionRequest(
        identityToken: payload.identityToken,
        authorizationCode: payload.authorizationCode,
        email: payload.email,
        fullName: payload.fullName
      )
      session = try await apiClient.createAppleSession(request)
    } catch {
      errorMessage = error.localizedDescription
    }

    isSigningIn = false
  }

  func signOut() {
    session = nil
    errorMessage = nil
  }
}

struct AppleAuthorizationPayload {
  let identityToken: String
  let authorizationCode: String?
  let email: String?
  let fullName: String?
}

@MainActor
private final class AppleAuthorizationBroker: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private var continuation: CheckedContinuation<AppleAuthorizationPayload, Error>?

  func requestAuthorization() async throws -> AppleAuthorizationPayload {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation

      let request = ASAuthorizationAppleIDProvider().createRequest()
      request.requestedScopes = [.fullName, .email]

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      controller.performRequests()
    }
  }

  nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    DispatchQueue.main.sync {
      UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    Task { @MainActor in
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
        continuation?.resume(throwing: AuthError.invalidCredential)
        continuation = nil
        return
      }

      guard
        let identityTokenData = credential.identityToken,
        let identityToken = String(data: identityTokenData, encoding: .utf8)
      else {
        continuation?.resume(throwing: AuthError.missingIdentityToken)
        continuation = nil
        return
      }

      let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
      let fullName = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())

      continuation?.resume(
        returning: AppleAuthorizationPayload(
          identityToken: identityToken,
          authorizationCode: authorizationCode,
          email: credential.email,
          fullName: fullName.isEmpty ? nil : fullName
        )
      )
      continuation = nil
    }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    Task { @MainActor in
      continuation?.resume(throwing: error)
      continuation = nil
    }
  }
}

enum AuthError: LocalizedError {
  case invalidCredential
  case missingIdentityToken

  var errorDescription: String? {
    switch self {
    case .invalidCredential:
      return "Sign in with Apple returned an unsupported credential."
    case .missingIdentityToken:
      return "Sign in with Apple did not return an identity token."
    }
  }
}
