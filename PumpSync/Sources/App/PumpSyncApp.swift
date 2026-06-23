import SwiftUI

@main
struct PumpSyncApp: App {
  @State private var services: AppServices

  init() {
#if DEBUG
    let services = AppLaunchEnvironment.isScreenshotMode ? AppServices.screenshotFixture() : AppServices.live()
#else
    let services = AppServices.live()
#endif
    services.backgroundSyncScheduler.register {
      await services.syncCoordinator.performBackgroundSync()
    }
    _services = State(initialValue: services)
  }

  var body: some Scene {
    WindowGroup {
      AppView()
        .environment(services)
        .task {
          services.backgroundSyncScheduler.scheduleDailySync()
        }
    }
  }
}
