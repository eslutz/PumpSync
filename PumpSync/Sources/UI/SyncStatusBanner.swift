import Foundation

enum SyncStatusAction: Equatable {
  case retry
  case openSubscription
  case openSettings
}

struct SyncStatusPresentation: Equatable {
  let title: String
  let detail: String
  let systemImage: String
  let actionTitle: String?
  let action: SyncStatusAction?
  let showsProgress: Bool

  static func make(for state: SyncOperationState, now: Date) -> SyncStatusPresentation? {
    switch state {
    case .idle:
      return nil
    case .running(let progress):
      guard progress.trigger != .background else {
        return nil
      }
      return running(progress, now: now)
    case .succeeded(let completion):
      return SyncStatusPresentation(
        title: "Sync complete",
        detail: completion.message,
        systemImage: "checkmark.circle.fill",
        actionTitle: nil,
        action: nil,
        showsProgress: false
      )
    case .failed(let failure):
      let action: (String, SyncStatusAction)? = switch failure.recovery {
      case .retry, .none:
        ("Try Again", .retry)
      case .openSubscription:
        ("View Subscription", .openSubscription)
      case .openSettings:
        ("Connection Settings", .openSettings)
      case .waitAndRetry:
        ("Try Again Later", .retry)
      }
      return SyncStatusPresentation(
        title: failure.recovery == .openSubscription ? "Subscription required" : "Sync needs attention",
        detail: failure.message,
        systemImage: "exclamationmark.triangle.fill",
        actionTitle: action?.0,
        action: action?.1,
        showsProgress: false
      )
    }
  }

  private static func running(_ progress: SyncProgress, now: Date) -> SyncStatusPresentation {
    let detail = switch progress.phase {
    case .preparing where now.timeIntervalSince(progress.startedAt) >= 3:
      "This can take about 30 seconds after inactivity. Keep PumpSync open."
    case .preparing:
      "Connecting securely…"
    case .downloading:
      "Retrieving available pump history."
    case .updatingHealth:
      "Saving new pump samples to Apple Health."
    }
    return SyncStatusPresentation(
      title: progress.phase.message,
      detail: detail,
      systemImage: "arrow.triangle.2.circlepath",
      actionTitle: nil,
      action: nil,
      showsProgress: true
    )
  }
}
