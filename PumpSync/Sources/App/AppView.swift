import SwiftUI
import UIKit

struct AppView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var maximumFormWidth: CGFloat = 680
  @State private var selectedTab: AppTab = .sync
  @State private var settingsNavigationID = UUID()
  @State private var syncNavigationID = UUID()
  @State private var editingScreenDepartureID = UUID()
  @State private var syncMessage: SyncMessage?
  @State private var initializedMessages = false

  var body: some View {
    // A single TabView hierarchy adapts between a tab bar (iPhone/compact) and
    // a sidebar (iPad/regular) on its own. The previous horizontalSizeClass
    // branch rebuilt the entire view hierarchy on every size-class change
    // (e.g. iPad Split View resize, Stage Manager), discarding any in-progress
    // navigation or form state; this keeps one NavigationStack per tab across
    // size-class transitions.
    TabView(selection: $selectedTab) {
      ForEach(AppTab.allCases) { tab in
        Tab(tab.title, systemImage: tab.systemImage, value: tab) {
          GeometryReader { column in
            let margin = (column.size.width - maximumFormWidth) / 2
            VStack(spacing: 0) {
              NavigationStack {
                tab.content
                  .toolbarTitleDisplayMode(margin > 20 ? .inline : .automatic)
              }
              .id(tab == .settings ? settingsNavigationID : syncNavigationID)
              .contentMargins(.horizontal, margin > 20 ? margin : nil, for: .scrollContent)
              if tab == .settings, usesSettingsMessageInset, let syncMessage {
                // Give both the large-text form and the message their own scrollable area.
                messageBanner(syncMessage, height: max(140, column.size.height * 0.36), alignment: .bottom)
                  .padding(.bottom, 8)
              }
            }
          }
        }
      }
    }
    .environment(\.editingScreenDepartureID, editingScreenDepartureID)
    .environment(\.recoverSync, recoverSync)
    .tabViewStyle(.sidebarAdaptable)
    .onChange(of: selectedTab) { _, _ in editingScreenDepartureID = UUID() }
    .overlay {
      GeometryReader { geometry in
        syncMessageOverlay(size: geometry.size)
      }
    }
    #if DEBUG
    .modifier(SyncFeedbackSequenceFixture())
    #endif
    .onAppear {
      guard !initializedMessages else { return }
      initializedMessages = true
      syncMessage = SyncMessage.make(for: services.syncCoordinator.operationState, id: UUID())
    }
    .onChange(of: services.syncCoordinator.operationState) { oldState, state in
      syncMessage = SyncMessage.make(for: state, id: UUID())
      let announcement: String?
      switch state {
      case .succeeded(let completion): announcement = ["Sync complete.", completion.message, completion.notice].compactMap { $0 }.joined(separator: " ")
      case .failed(let failure): announcement = failure.message
      case .running(let progress):
        // Announce the start once; changing every phase must not steal speech
        // from the screen the person is currently reading.
        if case .running = oldState { announcement = nil }
        else { announcement = progress.trigger == .background ? nil : "Sync started." }
      case .idle: announcement = nil
      }
      if let announcement { UIAccessibility.post(notification: .announcement, argument: announcement) }
    }
  }

  private var usesSettingsMessageInset: Bool {
    selectedTab == .settings && horizontalSizeClass == .compact && dynamicTypeSize.isAccessibilitySize
  }

  @ViewBuilder
  private func syncMessageOverlay(size: CGSize) -> some View {
    if let syncMessage, !usesSettingsMessageInset {
      let wideWindow = horizontalSizeClass == .regular && size.height >= 560
      let useBottomEdge = selectedTab == .settings || wideWindow
      let alignment: Alignment = useBottomEdge ? .bottom : .top
      // On compact Settings screens leave room for the floating system tab bar.
      let bottomInset: CGFloat = wideWindow ? 20 : 76
      messageBanner(syncMessage, height: max(140, size.height * 0.45), alignment: alignment)
        .padding(useBottomEdge ? .bottom : .top, useBottomEdge ? bottomInset : 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
  }

  private func messageBanner(_ message: SyncMessage, height: CGFloat, alignment: Alignment) -> some View {
    SyncMessageBanner(message: message, onDismiss: { syncMessage = nil }, onRecover: recoverSync,
                      maxHeight: height, alignment: alignment)
      .id(message.id)
      .frame(maxWidth: 520)
      .padding(.horizontal, 16)
  }

  private func recoverSync(_ action: SyncStatusAction) {
    syncMessage = nil
    switch action {
    case .retry:
      services.syncCoordinator.retry()
    case .openSettings:
      editingScreenDepartureID = UUID()
      settingsNavigationID = UUID()
      selectedTab = .settings
    }
  }
}

enum AppTab: String, CaseIterable, Identifiable {
  case sync
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .sync:
      return "Sync"
    case .settings:
      return "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .sync:
      return "arrow.triangle.2.circlepath"
    case .settings:
      return "gearshape"
    }
  }

  @ViewBuilder
  @MainActor
  var content: some View {
    switch self {
    case .sync:
      SyncView()
    case .settings:
      SettingsView()
    }
  }
}

private struct RecoverSyncKey: EnvironmentKey {
  static let defaultValue: @MainActor (SyncStatusAction) -> Void = { _ in }
}

private struct EditingScreenDepartureKey: EnvironmentKey {
  static let defaultValue = UUID()
}

extension EnvironmentValues {
  var editingScreenDepartureID: UUID {
    get { self[EditingScreenDepartureKey.self] }
    set { self[EditingScreenDepartureKey.self] = newValue }
  }

  var recoverSync: @MainActor (SyncStatusAction) -> Void {
    get { self[RecoverSyncKey.self] }
    set { self[RecoverSyncKey.self] = newValue }
  }
}
