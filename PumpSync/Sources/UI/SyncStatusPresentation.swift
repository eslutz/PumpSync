import Foundation

enum SyncStatusAction: Equatable {
  case retry
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
      case .retry:
        ("Try Again", .retry)
      case .none:
        nil
      case .openSettings:
        ("Open Settings", .openSettings)
      case .waitAndRetry:
        ("Try Again Later", .retry)
      }
      return SyncStatusPresentation(
        title: "Sync needs attention",
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
      "Keep PumpSync open while it connects to Tandem."
    case .preparing:
      "Connecting to Tandem…"
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
