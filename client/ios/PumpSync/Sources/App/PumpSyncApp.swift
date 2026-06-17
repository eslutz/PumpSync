import SwiftUI

@main
struct PumpSyncApp: App {
  @State private var services: AppServices

  init() {
    let services = AppServices.live()
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
