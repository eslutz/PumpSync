import BackgroundTasks
import Foundation
import Synchronization
import UIKit

enum BackgroundExecutionOutcome: Equatable {
  case completed(Bool)
  case timedOut
}

enum BackgroundExecutionDeadline {
  static func run(
    timeout: Duration,
    operation: @escaping @Sendable () async -> Bool
  ) async -> BackgroundExecutionOutcome {
    await withCheckedContinuation { continuation in
      let completed = Mutex(false)
      let timeoutTaskBox = Mutex<Task<Void, Never>?>(nil)
      let finish: @Sendable (BackgroundExecutionOutcome) -> Void = { outcome in
        let shouldFinish = completed.withLock { completed in
          guard !completed else { return false }
          completed = true
          return true
        }
        guard shouldFinish else { return }
        timeoutTaskBox.withLock { task in
          task?.cancel()
          task = nil
        }
        continuation.resume(returning: outcome)
      }

      let work = Task {
        finish(.completed(await operation()))
      }
      let timeoutTask = Task {
        do {
          try await Task.sleep(for: timeout)
        } catch {
          return
        }
        work.cancel()
        finish(.timedOut)
      }
      let shouldStoreTimeout = completed.withLock { !$0 }
      if shouldStoreTimeout {
        timeoutTaskBox.withLock { $0 = timeoutTask }
      } else {
        timeoutTask.cancel()
      }
    }
  }
}

@MainActor
final class BackgroundSyncScheduler {
  private let identifier: String
  private var isRegistered = false
  private let onScheduleFailure: (@Sendable (any Error) -> Void)?
  private let onEvent: (@Sendable (String, String?) -> Void)?
  private let executionTimeout: Duration

  init(
    identifier: String,
    executionTimeout: Duration = .seconds(20),
    onScheduleFailure: (@Sendable (any Error) -> Void)? = nil,
    onEvent: (@Sendable (String, String?) -> Void)? = nil
  ) {
    self.identifier = identifier
    self.executionTimeout = executionTimeout
    self.onScheduleFailure = onScheduleFailure
    self.onEvent = onEvent
  }

  func register(handler: @escaping @Sendable () async -> Bool) {
    guard !isRegistered else {
      return
    }

    let onEvent = onEvent
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }

      onEvent?("Background sync task started", Self.runtimeContext())
      self.handle(task: task, handler: handler)
    }
    isRegistered = registered
    onEvent?(
      registered ? "Background sync task registered" : "Background sync task registration failed",
      Self.runtimeContext()
    )
  }

  func scheduleDailySync(trigger: String = "unspecified") {
    let identifier = identifier
    let onScheduleFailure = onScheduleFailure
    let onEvent = onEvent
    let runtimeContext = Self.runtimeContext()
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      let matchingRequests = requests.filter { $0.identifier == identifier }
      let descriptions = matchingRequests.map {
        BackgroundSyncDiagnostics.pendingRequestDescription(
          identifier: $0.identifier,
          earliestBeginDate: $0.earliestBeginDate
        )
      }
      let pendingMessage = ([runtimeContext, "trigger=\(trigger)", "count=\(matchingRequests.count)"] + descriptions)
        .joined(separator: " ")

      guard !requests.contains(where: { $0.identifier == identifier }) else {
        onEvent?("Background sync task already scheduled", pendingMessage)
        return
      }

      let request = BGAppRefreshTaskRequest(identifier: identifier)
      request.earliestBeginDate = Date(timeIntervalSinceNow: AppConstants.staleSyncInterval)

      do {
        try BGTaskScheduler.shared.submit(request)
        let requestMessage = BackgroundSyncDiagnostics.pendingRequestDescription(
          identifier: request.identifier,
          earliestBeginDate: request.earliestBeginDate
        )
        onEvent?("Background sync task scheduled", "\(runtimeContext) trigger=\(trigger) \(requestMessage)")
      } catch {
        // A swallowed submit failure (unregistered identifier, simulator
        // restrictions, too many pending requests) makes background sync
        // silently never run — surface it to diagnostics.
        onScheduleFailure?(error)
      }
    }
  }

  private func handle(task: BGTask, handler: @escaping @Sendable () async -> Bool) {
    scheduleDailySync(trigger: "taskLaunch")

    let onEvent = onEvent
    let startedAt = Date()
    // BGTask isn't Sendable, but setTaskCompleted(success:) is documented as
    // safe to call from any thread — that's the whole point of the method.
    // Box it so it can cross into the unstructured Task below without the
    // compiler needing (and being unable) to verify BGTask's own safety.
    let taskBox = UncheckedSendableBox(value: task)
    let hasCompleted = Mutex(false)
    // A local nested func isn't inferred @Sendable even when its captures
    // are, so this is called from both the Task body and expirationHandler
    // below as an explicitly @Sendable closure instead.
    let complete: @Sendable (Bool, Bool) -> Void = { success, cancelled in
      let shouldComplete = hasCompleted.withLock { completed in
        guard !completed else {
          return false
        }
        completed = true
        return true
      }

      if shouldComplete {
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
        onEvent?(
          success ? "Background sync task completed" : "Background sync task failed",
          "build=\(BackgroundSyncDiagnostics.buildNumber) elapsedMs=\(elapsedMs) cancelled=\(cancelled)"
        )
        taskBox.value.setTaskCompleted(success: success)
      }
    }

    let executionTimeout = executionTimeout
    let work = Task {
      let outcome = await BackgroundExecutionDeadline.run(timeout: executionTimeout, operation: handler)
      let cancelled = Task.isCancelled
      switch outcome {
      case .completed(let succeeded):
        complete(succeeded && !cancelled, cancelled)
      case .timedOut:
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
        onEvent?(
          "Background sync task deferred",
          "build=\(BackgroundSyncDiagnostics.buildNumber) reason=executionBudget elapsedMs=\(elapsedMs)"
        )
        complete(false, true)
      }
    }

    task.expirationHandler = {
      work.cancel()
      let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
      onEvent?("Background sync task expired", "build=\(BackgroundSyncDiagnostics.buildNumber) elapsedMs=\(elapsedMs)")
      complete(false, true)
    }
  }

  private static func runtimeContext() -> String {
    let refreshStatus: BackgroundRefreshAvailability
    switch UIApplication.shared.backgroundRefreshStatus {
    case .available:
      refreshStatus = .available
    case .denied:
      refreshStatus = .denied
    case .restricted:
      refreshStatus = .restricted
    @unknown default:
      refreshStatus = .unknown
    }

    return BackgroundSyncDiagnostics.schedulingContext(
      buildNumber: BackgroundSyncDiagnostics.buildNumber,
      refreshStatus: refreshStatus,
      isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
    )
  }
}

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
  let value: Value
}
