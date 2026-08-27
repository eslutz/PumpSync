import SwiftUI

enum SyncStatusAction: Equatable {
  case viewSync
  case retry
  case openSubscription
  case openSettings
  case dismiss
}

struct SyncStatusPresentation: Equatable {
  let title: String
  let detail: String
  let systemImage: String
  let actionTitle: String?
  let action: SyncStatusAction?
  let showsProgress: Bool
  let autoDismissAfter: TimeInterval?

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
        showsProgress: false,
        autoDismissAfter: 8
      )
    case .failed(let failure):
      let action: (String, SyncStatusAction)? = switch failure.recovery {
      case .retry:
        ("Try Again", .retry)
      case .openSubscription:
        ("View Subscription", .openSubscription)
      case .openSettings:
        ("Open Settings", .openSettings)
      case .waitAndRetry, .none:
        nil
      }
      return SyncStatusPresentation(
        title: failure.recovery == .openSubscription ? "Subscription required" : "Sync needs attention",
        detail: failure.message,
        systemImage: "exclamationmark.triangle.fill",
        actionTitle: action?.0,
        action: action?.1,
        showsProgress: false,
        autoDismissAfter: nil
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
      actionTitle: "View",
      action: .viewSync,
      showsProgress: true,
      autoDismissAfter: nil
    )
  }
}

struct SyncStatusBanner: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let operationState: SyncOperationState
  let onViewSync: () -> Void
  let onRetry: () -> Void
  let onOpenSubscription: () -> Void
  let onOpenSettings: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    Group {
      if case .running = operationState {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          banner(at: context.date)
        }
      } else {
        banner(at: Date())
      }
    }
    .animation(reduceMotion ? nil : .snappy, value: operationState)
    .task(id: operationState) {
      guard let delay = SyncStatusPresentation.make(for: operationState, now: Date())?.autoDismissAfter else {
        return
      }
      let expectedState = operationState
      do {
        try await Task.sleep(for: .seconds(delay))
      } catch {
        return
      }
      guard operationState == expectedState else {
        return
      }
      onDismiss()
    }
  }

  @ViewBuilder
  private func banner(at date: Date) -> some View {
    if let presentation = SyncStatusPresentation.make(for: operationState, now: date) {
      HStack(alignment: .center, spacing: 12) {
        if presentation.showsProgress {
          ProgressView()
            .controlSize(.regular)
            .accessibilityHidden(true)
        } else {
          Image(systemName: presentation.systemImage)
            .font(.title3)
            .foregroundStyle(iconTint)
            .accessibilityHidden(true)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(presentation.title)
            .font(.subheadline.weight(.semibold))
          Text(presentation.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let actionTitle = presentation.actionTitle, let action = presentation.action {
          Button(actionTitle) {
            perform(action)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }

        if !presentation.showsProgress {
          Button(action: onDismiss) {
            Image(systemName: "xmark")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Dismiss notification")
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.08))
      }
      .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(presentation.title)
      .accessibilityValue(presentation.detail)
      .transition(.move(edge: .top).combined(with: .opacity))
    }
  }

  private var iconTint: Color {
    if case .succeeded = operationState {
      return .green
    }
    return .orange
  }

  private func perform(_ action: SyncStatusAction) {
    switch action {
    case .viewSync:
      onViewSync()
    case .retry:
      onRetry()
    case .openSubscription:
      onOpenSubscription()
    case .openSettings:
      onOpenSettings()
    case .dismiss:
      onDismiss()
    }
  }
}
