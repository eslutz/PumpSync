import SwiftUI

struct AppView: View {
  @Environment(AppServices.self) private var services
  @State private var selectedTab: AppTab = .dashboard

  var body: some View {
    TabView(selection: $selectedTab) {
      ForEach(AppTab.allCases) { tab in
        NavigationStack {
          tab.content
        }
        .tabItem { tab.label }
        .tag(tab)
      }
    }
    .task {
      await services.syncCoordinator.refreshIfStale(reason: .appOpen)
    }
  }
}

enum AppTab: String, CaseIterable, Identifiable {
  case dashboard
  case sync
  case settings

  var id: String { rawValue }

  @ViewBuilder
  var content: some View {
    switch self {
    case .dashboard:
      DashboardView()
    case .sync:
      SyncView()
    case .settings:
      SettingsView()
    }
  }

  @ViewBuilder
  var label: some View {
    switch self {
    case .dashboard:
      Label("Status", systemImage: "heart.text.square")
    case .sync:
      Label("Sync", systemImage: "arrow.triangle.2.circlepath")
    case .settings:
      Label("Settings", systemImage: "gearshape")
    }
  }
}
