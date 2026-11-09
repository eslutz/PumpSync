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

/// Intended for `.overlay`, so appearing or dismissing never changes page layout.
struct SyncMessageBanner: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  let message: SyncMessage
  let onDismiss: () -> Void
  let onRecover: (SyncStatusAction) -> Void
  var maxHeight: CGFloat = 320

  var body: some View {
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
    .background {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.regularMaterial))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        .allowsHitTesting(false)
    }
    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    .frame(maxHeight: maxHeight, alignment: .top)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("SyncMessageBanner")
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
