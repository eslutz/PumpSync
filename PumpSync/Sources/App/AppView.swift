import SwiftUI
import UIKit

struct AppView: View {
  @Environment(AppServices.self) private var services
  @State private var selectedTab: AppTab = .sync
  @State private var settingsNavigationID = UUID()
  @State private var syncNavigationID = UUID()
  @State private var editingScreenDepartureID = UUID()
  @State private var sheet: AppSheet?
  @State private var syncMessage: SyncMessage?
  @State private var initializedMessages = false

  private enum AppSheet: String, Identifiable {
    case subscription
    var id: String { rawValue }
  }

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
          NavigationStack {
            tab.content
          }
          .id(tab == .settings ? settingsNavigationID : syncNavigationID)
        }
      }
    }
    .environment(\.openConnectionSettings, {
      editingScreenDepartureID = UUID()
      settingsNavigationID = UUID()
      selectedTab = .settings
    })
    .environment(\.editingScreenDepartureID, editingScreenDepartureID)
    .environment(\.recoverSync, recoverSync)
    .tabViewStyle(.sidebarAdaptable)
    .onChange(of: selectedTab) { _, _ in editingScreenDepartureID = UUID() }
    .sheet(item: $sheet) { destination in
      NavigationStack {
        switch destination {
        case .subscription:
          SubscriptionSettingsView()
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { sheet = nil }
              }
            }
        }
      }
    }
    .overlay(alignment: .top) {
      GeometryReader { geometry in
        if let syncMessage {
          SyncMessageBanner(
            message: syncMessage,
            onDismiss: { self.syncMessage = nil },
            onRecover: recoverSync,
            maxHeight: max(140, geometry.size.height * 0.45)
          )
          .id(syncMessage.id)
          .frame(maxWidth: 520)
          .padding(.horizontal, 16)
          .padding(.top, 60)
          .frame(maxWidth: .infinity, alignment: .top)
        }
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

  private func recoverSync(_ action: SyncStatusAction) {
    syncMessage = nil
    switch action {
    case .retry:
      services.syncCoordinator.retry()
    case .openSettings:
      editingScreenDepartureID = UUID()
      settingsNavigationID = UUID()
      selectedTab = .settings
    case .openSubscription:
      editingScreenDepartureID = UUID()
      sheet = .subscription
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

private struct OpenConnectionSettingsKey: EnvironmentKey {
  static let defaultValue: @MainActor () -> Void = {}
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

  var openConnectionSettings: @MainActor () -> Void {
    get { self[OpenConnectionSettingsKey.self] }
    set { self[OpenConnectionSettingsKey.self] = newValue }
  }
}
