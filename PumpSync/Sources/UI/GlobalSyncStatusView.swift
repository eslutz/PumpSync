import SwiftUI

struct GlobalSyncStatusView: View {
  private enum StatusSheet: String, Identifiable { case details, subscription; var id: String { rawValue } }
  @Environment(AppServices.self) private var services
  @Environment(\.openConnectionSettings) private var openConnectionSettings
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var dismissedCompletion: Date?
  @State private var sheet: StatusSheet?

  private var completionDate: Date? {
    if case .succeeded(let completion) = services.syncCoordinator.operationState { return completion.completedAt }
    return nil
  }

  var body: some View {
    Group {
      if case .running(let progress) = services.syncCoordinator.operationState, progress.trigger != .background {
        TimelineView(.periodic(from: .now, by: 1)) { context in status(now: context.date) }
      } else { status(now: Date()) }
    }
      .sheet(item: $sheet) { destination in
        switch destination {
        case .subscription:
          NavigationStack {
            SubscriptionSettingsView()
              .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
          }
        case .details:
          NavigationStack {
            Form {
              if let presentation = SyncStatusPresentation.make(for: services.syncCoordinator.operationState, now: Date()) {
                SyncRecoveryContent(presentation: presentation, recover: recover)
              }
            }
            .navigationTitle("Sync Details")
            .toolbar { Button("Done") { sheet = nil } }
          }
        }
      }
  }

  @ViewBuilder private func status(now: Date) -> some View {
    if let presentation = SyncStatusPresentation.make(for: services.syncCoordinator.operationState, now: now),
       completionDate == nil || completionDate != dismissedCompletion {
      VStack(alignment: .leading, spacing: 8) {
        if dynamicTypeSize.isAccessibilitySize {
          Menu {
            if let title = presentation.actionTitle, let action = presentation.action {
              Button(title) { recover(action) }
            }
            Button("Sync Details") { sheet = .details }
            if !presentation.showsProgress && completionDate == nil {
              Button("Dismiss Sync Message") { services.syncCoordinator.dismissResult() }
            }
          } label: {
            Label(presentation.title, systemImage: presentation.systemImage)
              .font(.headline).fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
          .accessibilityIdentifier("GlobalSyncStatusActions")
        } else {
          HStack(alignment: .top, spacing: 12) {
            if presentation.showsProgress && !reduceMotion { ProgressView().accessibilityHidden(true) }
            else { Image(systemName: presentation.systemImage).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 4) {
              Text(presentation.title).font(.headline)
              Text(presentation.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            if !presentation.showsProgress && completionDate == nil {
              Button { services.syncCoordinator.dismissResult() } label: {
                Image(systemName: "xmark")
                  .frame(width: 44, height: 44).contentShape(Rectangle())
              }
              .buttonStyle(.plain).foregroundStyle(.primary)
              .accessibilityLabel("Dismiss Sync Message")
            }
          }
          if let title = presentation.actionTitle, let action = presentation.action {
            Button(title) { recover(action) }.buttonStyle(.glass).controlSize(.large)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(.bar)
      .accessibilityIdentifier("GlobalSyncStatus")
      .task(id: completionDate) {
        guard let date = completionDate else { return }
        do { try await Task.sleep(for: .seconds(max(0, 8 - Date().timeIntervalSince(date)))) }
        catch { return }
        dismissedCompletion = date
      }
    }
  }

  private func recover(_ action: SyncStatusAction) {
    switch action {
    case .retry: sheet = nil; services.syncCoordinator.retry()
    case .openSettings: sheet = nil; openConnectionSettings()
    case .openSubscription: sheet = .subscription
    }
  }
}


private struct SyncRecoveryContent: View {
  let presentation: SyncStatusPresentation
  let recover: (SyncStatusAction) -> Void

  var body: some View {
    Text(presentation.title).font(.headline)
    Text(presentation.detail)
    if let title = presentation.actionTitle, let action = presentation.action {
      Button(title) { recover(action) }.buttonStyle(.glass).controlSize(.large)
    }
  }
}

#Preview("Sync needs attention") {
  NavigationStack {
    Form {
      if let presentation = SyncStatusPresentation.make(
        for: .failed(SyncFailure(message: "The service is unavailable. Try again later.", recovery: .retry)), now: Date()) {
        SyncRecoveryContent(presentation: presentation, recover: { _ in })
      }
    }.navigationTitle("Sync Details")
  }
}
