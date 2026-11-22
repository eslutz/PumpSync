import SwiftUI

/// Only offer a cross-tab shortcut when there is an action to take.
enum SyncMessage: Equatable {
  case failed
  case healthAccess

  init?(for state: SyncOperationState) {
    switch state {
    case .failed(let failure) where failure.recovery != .none: self = .failed
    case .succeeded(let result) where result.permissionSkipped > 0: self = .healthAccess
    default: return nil
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .failed: "Sync needs attention"
    case .healthAccess: "Review Health access"
    }
  }
}

struct SyncMessageBanner: View {
  let message: SyncMessage
  let review: () -> Void
  let dismiss: () -> Void

  var body: some View {
    HStack {
      Button(action: review) {
        Label(message.title, systemImage: "exclamationmark.circle")
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Review Sync")
      .accessibilityIdentifier("SyncMessageActionButton")
      Button("Dismiss message", systemImage: "xmark", action: dismiss)
        .labelStyle(.iconOnly)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityIdentifier("DismissSyncMessageButton")
    }
    .padding(.horizontal)
    .background(.bar)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("SyncMessageBanner")
  }
}
