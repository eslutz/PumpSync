import BackgroundTasks
import Foundation
import Synchronization

final class BackgroundSyncScheduler {
  private let identifier: String
  private var isRegistered = false
  private let onScheduleFailure: (@Sendable (any Error) -> Void)?
  private let onEvent: (@Sendable (String) -> Void)?

  init(
    identifier: String,
    onScheduleFailure: (@Sendable (any Error) -> Void)? = nil,
    onEvent: (@Sendable (String) -> Void)? = nil
  ) {
    self.identifier = identifier
    self.onScheduleFailure = onScheduleFailure
    self.onEvent = onEvent
  }

  func register(handler: @escaping @Sendable () async -> Void) {
    guard !isRegistered else {
      return
    }

    let onEvent = onEvent
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }

      onEvent?("Background sync task started")
      self.handle(task: task, handler: handler)
    }
    isRegistered = true
  }

  func scheduleDailySync() {
    let identifier = identifier
    let onScheduleFailure = onScheduleFailure
    let onEvent = onEvent
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      guard !requests.contains(where: { $0.identifier == identifier }) else {
        onEvent?("Background sync task already scheduled")
        return
      }

      let request = BGAppRefreshTaskRequest(identifier: identifier)
      request.earliestBeginDate = Date(timeIntervalSinceNow: AppConstants.staleSyncInterval)

      do {
        try BGTaskScheduler.shared.submit(request)
        onEvent?("Background sync task scheduled")
      } catch {
        // A swallowed submit failure (unregistered identifier, simulator
        // restrictions, too many pending requests) makes background sync
        // silently never run — surface it to diagnostics.
        onScheduleFailure?(error)
      }
    }
  }

  private func handle(task: BGTask, handler: @escaping @Sendable () async -> Void) {
    scheduleDailySync()

    let onEvent = onEvent
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
        onEvent?(success ? "Background sync task completed" : "Background sync task failed")
        taskBox.value.setTaskCompleted(success: success)
      }
    }

    let work = Task {
      await handler()
      complete(!Task.isCancelled)
    }

    task.expirationHandler = {
      work.cancel()
      onEvent?("Background sync task expired")
      complete(false)
    }
  }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
  let value: Value
}
