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
        .task(id: scenePhase) {
          switch scenePhase {
          case .active:
            // This is the only foreground bootstrap path. AppView is also
            // constructed for a BGTask launch, so it must not own app-open
            // recovery or sync work.
            services.backgroundSyncScheduler.scheduleDailySync(trigger: "appActive")
            services.healthKitService.refreshAuthorizationStatus()
            await services.authService.recoverSessionIfNeeded()
            await services.syncCoordinator.refreshIfStale(reason: .appOpen)
          case .background:
            services.backgroundSyncScheduler.scheduleDailySync(trigger: "appBackground")
          default:
            break
          }
        }
    }
  }
}
