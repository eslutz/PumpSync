import SwiftUI

/// A presentation-only message. Dismissing it never changes the sync result.
struct SyncMessage: Identifiable, Equatable {
  let id: UUID
  let title: String
  let detail: String
  let systemImage: String
  let actionTitle: String?
  let action: SyncStatusAction?

  /// Supply a new ID once for each event, rather than on each view evaluation.
  static func make(for state: SyncOperationState, id: UUID) -> SyncMessage? {
    switch state {
    case .failed:
      guard let presentation = SyncStatusPresentation.make(for: state, now: Date()) else { return nil }
      return SyncMessage(id: id, title: presentation.title, detail: presentation.detail,
                         systemImage: presentation.systemImage,
                         actionTitle: presentation.actionTitle, action: presentation.action)
    case .succeeded(let completion):
      guard let notice = completion.notice?.trimmingCharacters(in: .whitespacesAndNewlines),
            !notice.isEmpty else { return nil }
      return SyncMessage(id: id, title: "Sync completed with a notice", detail: notice,
                         systemImage: "info.circle.fill", actionTitle: nil, action: nil)
    case .idle, .running:
      return nil
    }
  }
}

/// Interactive sync feedback shared by the floating and large-text Settings presentations.
struct SyncMessageBanner: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  let message: SyncMessage
  let onDismiss: () -> Void
  let onRecover: (SyncStatusAction) -> Void
  var maxHeight: CGFloat = 320
  var alignment: Alignment = .top

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    Group {
      if reduceTransparency {
        bannerContent.background(Color(uiColor: .secondarySystemBackground), in: shape)
      } else {
        bannerContent.glassEffect(.regular, in: shape)
      }
    }
    .frame(maxHeight: maxHeight, alignment: alignment)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("SyncMessageBanner")
  }

  private var bannerContent: some View {
    HStack(alignment: .top, spacing: 8) {
      ViewThatFits(in: .vertical) {
        messageContent
        ScrollView {
          messageContent.frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss message")
      .accessibilityHint("The sync result remains available on the Sync screen")
      .accessibilityIdentifier("DismissSyncMessageButton")
    }
    .padding(16)
    .frame(maxWidth: 560, alignment: .leading)
  }

  private var messageContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(message.title, systemImage: message.systemImage)
        .font(.headline)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      Text(message.detail)
        .font(.body)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("SyncMessageDetail")
      if let actionTitle = message.actionTitle, let action = message.action {
        Button { onRecover(action) } label: {
          Text(actionTitle)
            .frame(minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
        }
          .buttonStyle(.bordered)
          .accessibilityIdentifier("SyncMessageActionButton")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}
