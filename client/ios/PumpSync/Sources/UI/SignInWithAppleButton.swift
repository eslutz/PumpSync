import AuthenticationServices
import SwiftUI

struct SignInWithAppleButton: UIViewRepresentable {
  var isEnabled: Bool
  var action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
    let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
    button.cornerRadius = 8
    button.addTarget(context.coordinator, action: #selector(Coordinator.performAction), for: .touchUpInside)
    return button
  }

  func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
    uiView.isEnabled = isEnabled
    uiView.alpha = isEnabled ? 1 : 0.55
  }

  final class Coordinator: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc func performAction() {
      action()
    }
  }
}
