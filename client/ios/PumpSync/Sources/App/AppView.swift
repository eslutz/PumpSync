import SwiftUI

struct AppView: View {
  @Environment(AppServices.self) private var services
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var selectedTab: AppTab = .sync

  var body: some View {
    Group {
      if horizontalSizeClass == .regular {
        NavigationSplitView {
          List {
            ForEach(AppTab.allCases) { tab in
              Button {
                selectedTab = tab
              } label: {
                Label(tab.title, systemImage: tab.systemImage)
              }
              .buttonStyle(.plain)
              .listRowBackground(selectedTab == tab ? Color(.secondarySystemGroupedBackground) : Color.clear)
              .accessibilityValue(selectedTab == tab ? "Selected" : "")
              .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
          }
          .listStyle(.sidebar)
          .navigationTitle("PumpSync")
        } detail: {
          NavigationStack {
            selectedTab.content
          }
        }
      } else {
        TabView(selection: $selectedTab) {
          ForEach(AppTab.allCases) { tab in
            NavigationStack {
              tab.content
            }
            .tabItem { tab.label }
            .tag(tab)
          }
        }
      }
    }
    .task {
      await services.syncCoordinator.refreshIfStale(reason: .appOpen)
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
  var content: some View {
    switch self {
    case .sync:
      SyncView()
    case .settings:
      SettingsView()
    }
  }

  @ViewBuilder
  var label: some View {
    Label(title, systemImage: systemImage)
  }
}
