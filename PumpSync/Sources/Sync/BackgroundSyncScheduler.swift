import BackgroundTasks
import Foundation
import Synchronization

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
    let identifier = identifier
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      guard !requests.contains(where: { $0.identifier == identifier }) else {
        return
      }

      let request = BGProcessingTaskRequest(identifier: identifier)
      request.requiresNetworkConnectivity = true
      request.requiresExternalPower = false
      request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)

      try? BGTaskScheduler.shared.submit(request)
    }
  }

  private func handle(task: BGTask, handler: @escaping @Sendable () async -> Void) {
    scheduleDailySync()

    // BGTask isn't Sendable, but setTaskCompleted(success:) is documented as
    // safe to call from any thread — that's the whole point of the method.
    // Box it so it can cross into the unstructured Task below without the
    // compiler needing (and being unable) to verify BGTask's own safety.
    let taskBox = UncheckedSendableBox(value: task)
    let hasCompleted = Mutex(false)
    // A local nested func isn't inferred @Sendable even when its captures
    // are, so this is called from both the Task body and expirationHandler
    // below as an explicitly @Sendable closure instead.
    let complete: @Sendable (Bool) -> Void = { success in
      let shouldComplete = hasCompleted.withLock { completed in
        guard !completed else {
          return false
        }
        completed = true
        return true
      }

      if shouldComplete {
        taskBox.value.setTaskCompleted(success: success)
      }
    }

    let work = Task {
      await handler()
      complete(!Task.isCancelled)
    }

    task.expirationHandler = {
      work.cancel()
      complete(false)
    }
  }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
  let value: Value
}
