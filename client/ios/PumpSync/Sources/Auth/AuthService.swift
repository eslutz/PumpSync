import AuthenticationServices
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AuthService {
  private let authorizeWithApple: @MainActor () async throws -> AppleAuthorizationPayload
  private let createAppleSession: @MainActor (AppleSessionRequest) async throws -> AppleSessionResponse
  private let diagnostics: DiagnosticsLogStore?

  private(set) var session: AppleSessionResponse?
  private(set) var isSigningIn = false
  private(set) var statusMessage = "Not signed in."
  var errorMessage: String?

  init(apiClient: PumpSyncAPIClient, diagnostics: DiagnosticsLogStore? = nil) {
    let authorizationBroker = AppleAuthorizationBroker()
    authorizeWithApple = {
      try await authorizationBroker.requestAuthorization()
    }
    createAppleSession = { request in
      try await apiClient.createAppleSession(request)
    }
    self.diagnostics = diagnostics
  }

  init(
    authorizeWithApple: @escaping @MainActor () async throws -> AppleAuthorizationPayload,
    createAppleSession: @escaping @MainActor (AppleSessionRequest) async throws -> AppleSessionResponse,
    diagnostics: DiagnosticsLogStore? = nil
  ) {
    self.authorizeWithApple = authorizeWithApple
    self.createAppleSession = createAppleSession
    self.diagnostics = diagnostics
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
    statusMessage = "Signing in..."
    diagnostics?.record(source: .auth, title: "Sign in started")

    do {
      let payload = try await authorizeWithApple()
      diagnostics?.record(source: .auth, title: "Apple authorization completed")
      let request = AppleSessionRequest(
        identityToken: payload.identityToken,
        authorizationCode: payload.authorizationCode,
        email: payload.email,
        fullName: payload.fullName
      )
      session = try await createAppleSession(request)
      statusMessage = "Signed in as \(session?.user.email ?? "Apple account")."
      diagnostics?.record(source: .auth, title: "PumpSync session created")
    } catch {
      let userMessage = Self.userMessage(for: error)
      errorMessage = userMessage
      statusMessage = userMessage
      diagnostics?.record(error: error, source: .auth, title: "Sign in failed")
    }

    isSigningIn = false
  }

  func signOut() {
    session = nil
    errorMessage = nil
    statusMessage = "Not signed in."
    diagnostics?.record(source: .auth, title: "Signed out")
  }

  static func userMessage(for error: Error) -> String {
    if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
      return "Sign in was canceled."
    }

    if let authError = error as? AuthError, authError == .authorizationTimedOut {
      return "Sign in did not finish. Try again."
    }

    return "Sign in could not be completed. Try again."
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
      let windowScenes = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }

      if let keyWindow = windowScenes
        .flatMap(\.windows)
        .first(where: \.isKeyWindow) {
        return keyWindow
      }

      if let windowScene = windowScenes.first {
        return UIWindow(windowScene: windowScene)
      }

      preconditionFailure("Sign in with Apple requires an active window scene.")
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

enum AuthError: LocalizedError, Equatable {
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
