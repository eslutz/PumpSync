import BackgroundTasks
import Foundation

final class BackgroundSyncScheduler {
  private let identifier: String
  private var isRegistered = false

  init(identifier: String) {
    self.identifier = identifier
  }

  func register(handler: @escaping @Sendable () async -> Void) {
    guard !isRegistered else {
      return
    }

    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }

      self.handle(task: task, handler: handler)
    }
    isRegistered = true
  }

  func scheduleDailySync() {
    let request = BGProcessingTaskRequest(identifier: identifier)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)

    try? BGTaskScheduler.shared.submit(request)
  }

  private func handle(task: BGTask, handler: @escaping @Sendable () async -> Void) {
    scheduleDailySync()

    let work = Task {
      await handler()
      task.setTaskCompleted(success: !Task.isCancelled)
    }

    task.expirationHandler = {
      work.cancel()
    }
  }
}
