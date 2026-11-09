#if DEBUG
import SwiftUI
import UIKit

/// Opt-in UI-test driver. Only synthetic screenshot services may reach it;
/// it changes presentation state without network requests or Health writes.
struct SyncFeedbackSequenceFixture: ViewModifier {
  @Environment(AppServices.self) private var services
  @State private var step = 0
  @State private var startedAt = Date()

  private var isEnabled: Bool {
    AppLaunchEnvironment.isScreenshotMode
      && ProcessInfo.processInfo.arguments.contains("--pumpsync-feedback-sequence")
  }

  func body(content: Content) -> some View {
    content.overlay(alignment: .topTrailing) {
      if isEnabled {
        Button {
          step += 1
          services.syncCoordinator.applyScreenshotFeedbackState(state(for: step))
        } label: {
          Image(systemName: "forward.end.alt")
            .font(.system(size: 18))
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Advance feedback fixture")
        .accessibilityValue("\(step)|\(UIApplication.shared.preferredContentSizeCategory.rawValue)")
        .accessibilityIdentifier("AdvanceFeedbackFixture")
        .padding(.trailing, 4)
      }
    }
  }

  private func state(for step: Int) -> SyncOperationState {
    switch step {
    case 1, 5:
      return .running(SyncProgress(phase: .preparing, trigger: .manual, startedAt: startedAt))
    case 2:
      return .running(SyncProgress(phase: .downloading, trigger: .manual, startedAt: startedAt))
    case 3:
      return .running(SyncProgress(phase: .updatingHealth, trigger: .manual, startedAt: startedAt))
    case 4, 6:
      return .failed(SyncFailure(
        message: "Sync could not be completed. Check your connection and try again. Your previously saved samples remain available in Apple Health.",
        recovery: .retry))
    case 7:
      return .succeeded(SyncCompletion(message: "Imported 4 new samples.", completedAt: startedAt,
        notice: "Some older pump history was unavailable. New records were saved successfully. Review the available history before assuming all older records have been imported."))
    default:
      return .succeeded(SyncCompletion(message: "Imported 4 new samples.", completedAt: startedAt))
    }
  }
}
#endif
