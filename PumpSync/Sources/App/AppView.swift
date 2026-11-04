import SwiftUI

struct AppView: View {
  @Environment(AppServices.self) private var services
  @State private var selectedTab: AppTab = .sync
  @State private var settingsNavigationID = UUID()
  @State private var syncNavigationID = UUID()

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
      settingsNavigationID = UUID()
      selectedTab = .settings
    })
    .tabViewStyle(.sidebarAdaptable)

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

extension EnvironmentValues {
  var openConnectionSettings: @MainActor () -> Void {
    get { self[OpenConnectionSettingsKey.self] }
    set { self[OpenConnectionSettingsKey.self] = newValue }
  }
}
