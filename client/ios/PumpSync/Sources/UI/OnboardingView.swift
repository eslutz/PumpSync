import SwiftUI

struct OnboardingView: View {
  var body: some View {
    PumpSyncScreen {
      GlassSection {
        VStack(spacing: 20) {
          Image(systemName: "heart.text.square")
            .font(.system(size: 48))
            .foregroundStyle(.tint)

          Text("PumpSync")
            .font(.largeTitle.bold())

          Text("Use Settings to sign in with Apple, add Tandem credentials on this device, and manage Apple Health access to begin syncing.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
    }
  }
}
