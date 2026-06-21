import SwiftUI

struct OnboardingView: View {
  var body: some View {
    PumpSyncScreen {
      GlassSection {
        VStack(spacing: 20) {
          Image(systemName: "heart.text.square")
            .font(.system(size: 48))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)

          Text("PumpSync")
            .font(.largeTitle.bold())

          Text("Use Settings to connect PumpSync or a self-hosted service, add your pump account on this device, and allow Apple Health writes to begin syncing.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
    }
  }
}
