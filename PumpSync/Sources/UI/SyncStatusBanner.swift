import SwiftUI

enum SyncStatusAction: Equatable {
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
      actionTitle: nil,
      action: nil,
      showsProgress: true,
      autoDismissAfter: nil
    )
  }
}

struct SyncStatusBanner: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let operationState: SyncOperationState
  let maximumHeight: CGFloat
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
  }

  @ViewBuilder
  private func banner(at date: Date) -> some View {
    if let presentation = SyncStatusPresentation.make(for: operationState, now: date) {
      BannerHeightLimit(maximumHeight: max(44, maximumHeight - 24)) {
        if dynamicTypeSize.isAccessibilitySize {
          scrollableContents(presentation)
            .frame(height: max(44, maximumHeight - 24))
        } else {
          // Long or localized messages can also overflow at standard sizes.
          // Preserve the compact row only while its full height fits.
          ViewThatFits(in: .vertical) {
            horizontalContents(presentation)
            scrollableContents(presentation)
          }
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
      .accessibilityElement(children: .contain)
      .accessibilityLabel(presentation.title)
      .transition(.move(edge: .top).combined(with: .opacity))
    }
  }

  private func horizontalContents(_ presentation: SyncStatusPresentation) -> some View {
    HStack(alignment: .center, spacing: 12) {
      statusIcon(presentation)
      message(presentation)

      if let actionTitle = presentation.actionTitle, let action = presentation.action {
        Button(actionTitle) {
          perform(action)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      dismissButton
    }
  }

  private func scrollableContents(_ presentation: SyncStatusPresentation) -> some View {
    VStack(spacing: 8) {
      HStack {
        statusIcon(presentation)
        Spacer(minLength: 0)
        dismissButton
      }
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 12) {
          message(presentation)
          if let actionTitle = presentation.actionTitle, let action = presentation.action {
            Button {
              perform(action)
            } label: {
              Text(actionTitle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollBounceBehavior(.basedOnSize)
      .accessibilityIdentifier("SyncStatusBannerContent")
    }
  }

  private func message(_ presentation: SyncStatusPresentation) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(presentation.title)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
      Text(presentation.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func statusIcon(_ presentation: SyncStatusPresentation) -> some View {
    if presentation.showsProgress && !reduceMotion {
      ProgressView()
        .controlSize(.regular)
        .accessibilityHidden(true)
    } else {
      Image(systemName: presentation.systemImage)
        .font(.title3)
        .foregroundStyle(iconTint)
        .accessibilityHidden(true)
    }
  }

  private var dismissButton: some View {
    Button(action: onDismiss) {
      Image(systemName: "xmark")
        // Leave room for pixel-aligned accessibility bounds to remain at least 44 points.
        .frame(width: 48, height: 48)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel("Dismiss notification")
    .accessibilityHint("Hides this notification without stopping the sync")
  }

  private var iconTint: Color {
    if case .succeeded = operationState {
      return .green
    }
    return .orange
  }

  private func perform(_ action: SyncStatusAction) {
    switch action {
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

// A flexible maximum frame reserves its entire height in a safe-area inset.
// Measure the compact row at its intrinsic height, then place ViewThatFits
// within a finite budget so long rows choose the scrollable alternative.
private struct BannerHeightLimit: Layout {
  let maximumHeight: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let content = subviews.first else { return .zero }
    let intrinsic = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
    return CGSize(width: intrinsic.width, height: min(intrinsic.height, maximumHeight))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    subviews.first?.place(
      at: bounds.origin,
      anchor: .topLeading,
      proposal: ProposedViewSize(bounds.size)
    )
  }
}
