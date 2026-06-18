import SwiftUI

struct OnboardingView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "heart.text.square")
        .font(.system(size: 48))
        .foregroundStyle(.tint)

      Text("PumpSync")
        .font(.largeTitle.bold())

      Text("Use Settings to sign in with Apple, add Tandem credentials on this device, and authorize Apple Health writes to begin syncing.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)

      if let message = services.authService.errorMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .padding()
  }
}
