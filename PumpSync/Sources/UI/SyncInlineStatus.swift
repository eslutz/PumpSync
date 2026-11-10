import SwiftUI

/// Reserves the phase copy's natural, Dynamic Type-aware size. Updating status
/// changes only the overlay, never the Form row's proposed height.
struct SyncInlineStatus: View {
  let state: SyncOperationState
  @Environment(\.recoverSync) private var recoverSync
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let presentation = SyncStatusPresentation.make(for: state, now: context.date)
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: presentation?.systemImage ?? "arrow.triangle.2.circlepath")
            .font(.system(size: 20))
            .opacity(presentation?.showsProgress == true && !reduceMotion ? 0 : 1)
            .overlay {
              if presentation?.showsProgress == true && !reduceMotion {
                ProgressView().controlSize(.small)
              }
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
          ZStack(alignment: .topLeading) {
            ForEach(["No sync in progress", "Starting secure service…", "Downloading pump data…",
                     "Updating Apple Health…", "Sync complete", "Subscription required", "Sync needs attention"], id: \.self) {
              Text($0).hidden().accessibilityHidden(true)
            }
          }
          .overlay(alignment: .topLeading) {
            Text(presentation?.title ?? "No sync in progress")
              .accessibilityIdentifier("SyncProgressTitle")
          }
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
        }
        ZStack(alignment: .topLeading) {
          ForEach(["This can take about 30 seconds after inactivity. Keep PumpSync open.",
                   "Saving new pump samples to Apple Health.",
                   "Retrieving available pump history.",
                   "Keep PumpSync open while syncing. You can move between screens."], id: \.self) {
            Text($0).hidden().accessibilityHidden(true)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 44)
        .overlay(alignment: .topLeading) {
          // Long server failures remain readable without moving neighboring
          // controls. Most messages fit and don't need scrolling.
          VStack(alignment: .leading, spacing: 0) {
            ScrollView {
              VStack(alignment: .leading, spacing: 8) {
                Text(presentation?.detail ?? "Keep PumpSync open while syncing. You can move between screens.")
                  .accessibilityIdentifier("SyncProgressDetail")
                if case .succeeded(let completion) = state, let notice = completion.notice {
                  Text(notice).accessibilityIdentifier("SyncCompletionDetail")
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
            }
            .scrollBounceBehavior(.basedOnSize)
            if let title = presentation?.actionTitle, let action = presentation?.action {
              Button { recoverSync(action) } label: {
                Text(title)
                  .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                  .contentShape(Rectangle())
              }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("SyncRecoveryButton")
            }
          }
        }
        .foregroundStyle(.primary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("SyncInlineStatus")
    }
  }
}
