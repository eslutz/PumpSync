import AuthenticationServices
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AuthService {
  private let authorizeWithApple: @MainActor () async throws -> AppleAuthorizationPayload
  private let createAppleSession: @MainActor (AppleSessionRequest) async throws -> AppleSessionResponse

  private(set) var session: AppleSessionResponse?
  private(set) var isSigningIn = false
  private(set) var statusMessage = "Not signed in."
  var errorMessage: String?

  init(apiClient: PumpSyncAPIClient) {
    let authorizationBroker = AppleAuthorizationBroker()
    authorizeWithApple = {
      try await authorizationBroker.requestAuthorization()
    }
    createAppleSession = { request in
      try await apiClient.createAppleSession(request)
    }
  }

  init(
    authorizeWithApple: @escaping @MainActor () async throws -> AppleAuthorizationPayload,
    createAppleSession: @escaping @MainActor (AppleSessionRequest) async throws -> AppleSessionResponse
  ) {
    self.authorizeWithApple = authorizeWithApple
    self.createAppleSession = createAppleSession
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
    statusMessage = "Waiting for Apple authentication..."

    do {
      let payload = try await authorizeWithApple()
      statusMessage = "Apple authenticated. Creating PumpSync session..."
      let request = AppleSessionRequest(
        identityToken: payload.identityToken,
        authorizationCode: payload.authorizationCode,
        email: payload.email,
        fullName: payload.fullName
      )
      session = try await createAppleSession(request)
      statusMessage = "Signed in as \(session?.user.email ?? "Apple account")."
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Sign in failed."
    }

    isSigningIn = false
  }

  func signOut() {
    session = nil
    errorMessage = nil
    statusMessage = "Not signed in."
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
  private var controller: ASAuthorizationController?
  private var timeoutTask: Task<Void, Never>?

  func requestAuthorization() async throws -> AppleAuthorizationPayload {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation

      let request = ASAuthorizationAppleIDProvider().createRequest()
      request.requestedScopes = [.fullName, .email]

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      self.controller = controller
      controller.performRequests()

      timeoutTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(45))
        self?.finish(throwing: AuthError.authorizationTimedOut)
      }
    }
  }

  private func finish(returning payload: AppleAuthorizationPayload) {
    continuation?.resume(returning: payload)
    clearRequestState()
  }

  private func finish(throwing error: Error) {
    continuation?.resume(throwing: error)
    clearRequestState()
  }

  private func clearRequestState() {
    continuation = nil
    controller = nil
    timeoutTask?.cancel()
    timeoutTask = nil
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
        finish(throwing: AuthError.invalidCredential)
        return
      }

      guard
        let identityTokenData = credential.identityToken,
        let identityToken = String(data: identityTokenData, encoding: .utf8)
      else {
        finish(throwing: AuthError.missingIdentityToken)
        return
      }

      let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
      let fullName = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())

      finish(
        returning:
        AppleAuthorizationPayload(
          identityToken: identityToken,
          authorizationCode: authorizationCode,
          email: credential.email,
          fullName: fullName.isEmpty ? nil : fullName
        )
      )
    }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    Task { @MainActor in
      finish(throwing: error)
    }
  }
}

enum AuthError: LocalizedError {
  case invalidCredential
  case missingIdentityToken
  case authorizationTimedOut

  var errorDescription: String? {
    switch self {
    case .invalidCredential:
      return "Sign in with Apple returned an unsupported credential."
    case .missingIdentityToken:
      return "Sign in with Apple did not return an identity token."
    case .authorizationTimedOut:
      return "Sign in with Apple did not finish. Try again."
    }
  }
}
