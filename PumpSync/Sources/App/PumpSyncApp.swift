import SwiftUI

@main
struct PumpSyncApp: App {
  @State private var services: AppServices
  @Environment(\.scenePhase) private var scenePhase

  init() {
#if DEBUG
    let services = AppLaunchEnvironment.isScreenshotMode ? AppServices.screenshotFixture() : AppServices.live()
#else
    let services = AppServices.live()
#endif
    services.backgroundSyncScheduler.register {
      await services.syncCoordinator.performBackgroundSync()
    }
    services.authService.startObservingTransactionUpdates()
    _services = State(initialValue: services)
  }

  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(services)
    }
    .onChange(of: scenePhase) { _, newPhase in
      switch newPhase {
      case .active:
        // AppView's .task only runs on cold launch; an app kept resident for
        // days and foregrounded again needs the same staleness check, which
        // the 20h stale interval keeps from over-syncing.
        Task {
          await services.syncCoordinator.refreshIfStale(reason: .appOpen)
        }
      case .background:
        services.backgroundSyncScheduler.scheduleDailySync()
      default:
        break
      }
    }
  }
}
