import SwiftUI

/// Owns only foreground bootstrap/retry work. BGTask work has its own owner.
@MainActor
final class ForegroundRecoveryController {
  private let setVisible: (Bool) -> Void
  private let recover: () async -> Void
  private var phase: ScenePhase = .background
  private var needsRecovery = true
  private var operationID: UUID?
  private var task: Task<Void, Never>?

  init(setVisible: @escaping (Bool) -> Void, recover: @escaping () async -> Void) {
    self.setVisible = setVisible
    self.recover = recover
  }

  func setScenePhase(_ next: ScenePhase) {
    phase = next
    setVisible(next != .background)
    if next == .background {
      task?.cancel()
      task = nil
      operationID = nil
      needsRecovery = true
    } else if next == .active && needsRecovery {
      needsRecovery = false
      startRecovery()
    }
  }

  func retryConnection() {
    guard phase != .background else { return }
    startRecovery()
  }

  private func startRecovery() {
    guard task == nil else { return }
    let id = UUID()
    operationID = id
    task = Task { [weak self] in
      guard let self, !Task.isCancelled else { return }
      await recover()
      if operationID == id {
        task = nil
        operationID = nil
      }
    }
  }
}
