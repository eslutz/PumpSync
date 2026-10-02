import Foundation
import Observation

/// Owns form work independently of transport cancellation. A stale completion
/// cannot clear a newer request's busy state after the form is reopened.
@MainActor
@Observable
final class CredentialValidationLifetime {
  private var task: Task<Void, Never>?
  private var operationID: UUID?
  private(set) var isRunning = false

  func start(operation: @escaping @MainActor () async -> Void) {
    cancel()
    let id = UUID()
    operationID = id
    isRunning = true
    task = Task {
      await operation()
      guard operationID == id else { return }
      task = nil
      operationID = nil
      isRunning = false
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
    operationID = nil
    isRunning = false
  }
}
