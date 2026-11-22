import SwiftUI

struct SyncInlineStatus: View {
  let status: SyncStatusPresentation
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Group {
          if status.showsProgress && !reduceMotion {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: status.systemImage).foregroundStyle(.tint)
          }
        }
        .accessibilityHidden(true)
        Text(status.title)
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("SyncProgressTitle")
      }
      if let detail = status.detail {
        Text(detail).accessibilityIdentifier("SyncProgressDetail")
      }
      if let notice = status.notice {
        Text(notice).accessibilityIdentifier("SyncCompletionDetail")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 4)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("SyncInlineStatus")
  }

}
