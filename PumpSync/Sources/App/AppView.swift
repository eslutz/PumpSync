import SwiftUI
import UIKit

struct AppView: View {
  @Environment(AppServices.self) private var services
  @ScaledMetric(relativeTo: .body) private var maximumFormWidth: CGFloat = 680
  @State private var selectedTab: AppTab = .sync
  @State private var syncPath: [SyncDestination] = []
  @State private var editingScreenDepartureID = UUID()
  @State private var syncMessage: SyncMessage?

  #if DEBUG
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  private var settingsAuditTabVisibility: Visibility {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let isAffectedLayout = UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
      && version.majorVersion == 27 && version.minorVersion == 2
    return isAffectedLayout && AppLaunchEnvironment.isScreenshotMode
      && ProcessInfo.processInfo.arguments.contains("--pumpsync-audit-without-system-tabs") ? .hidden : .automatic
  }
  #endif

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
            Group {
              if tab == .sync {
                NavigationStack(path: $syncPath) {
                  SyncView(navigate: { syncPath.append($0) }, maximumContentWidth: maximumFormWidth)
                    .toolbarTitleDisplayMode(margin > 20 ? .inline : .automatic)
                }
              } else {
                NavigationStack {
                  SettingsView().toolbarTitleDisplayMode(margin > 20 ? .inline : .automatic)
                }
                #if DEBUG
                .toolbarVisibility(settingsAuditTabVisibility, for: .tabBar)
                #endif
                .safeAreaInset(edge: .bottom, spacing: 0) {
                  if let syncMessage {
                    SyncMessageBanner(message: syncMessage, review: {
                      syncPath.removeAll()
                      selectedTab = .sync
                    }, dismiss: { self.syncMessage = nil })
                  }
                }
              }
            }
            .contentMargins(.horizontal, margin > 20 ? margin : nil, for: .scrollContent)
          }
        }
      }
    }
    .environment(\.editingScreenDepartureID, editingScreenDepartureID)
    .tabViewStyle(.sidebarAdaptable)
    .onChange(of: selectedTab) { _, tab in
      editingScreenDepartureID = UUID()
      if tab == .sync { syncMessage = nil }
    }
    #if DEBUG
    .modifier(SyncFeedbackSequenceFixture())
    #endif
    .onChange(of: services.syncCoordinator.operationState) { oldState, state in
      syncMessage = selectedTab == .settings ? SyncMessage(for: state) : nil
      let announcement: String?
      switch state {
      case .succeeded, .failed:
        announcement = SyncStatusPresentation.make(for: state, now: .now)?.announcement
      case .running(let progress):
        if case .running = oldState { announcement = nil }
        else { announcement = progress.trigger == .background ? nil : String(localized: "Sync started.") }
      case .idle:
        announcement = nil
      }
      if let announcement { UIAccessibility.post(notification: .announcement, argument: announcement) }
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

}

private struct EditingScreenDepartureKey: EnvironmentKey {
  static let defaultValue = UUID()
}

extension EnvironmentValues {
  var editingScreenDepartureID: UUID {
    get { self[EditingScreenDepartureKey.self] }
    set { self[EditingScreenDepartureKey.self] = newValue }
  }

}
