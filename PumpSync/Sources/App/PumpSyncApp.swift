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
      if newPhase == .background {
        services.backgroundSyncScheduler.scheduleDailySync()
      }
    }
  }
}
