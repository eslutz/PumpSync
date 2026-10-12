import SwiftUI

/// Owns only foreground bootstrap/retry work. BGTask work has its own owner.
@MainActor
final class ForegroundRecoveryController {
  private let setVisible: (Bool) -> Void
  private let recover: () async -> Void
  private var phase: ScenePhase = .background
  private var needsRecovery = true
  private var pendingReconciliation = false
  private var operationID: UUID?
  private var task: Task<Void, Never>?

  var isRecovering: Bool { task != nil }

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
    } else if next == .active {
      if pendingReconciliation || needsRecovery { startRecovery() }
    }
  }

  func retryConnection() {
    guard phase != .background else { return }
    startRecovery()
  }

  func observeSessionRecovery(_ authService: AuthService, syncCoordinator: SyncCoordinator) {
    authService.setSessionEstablishedHandler { [weak self, weak syncCoordinator] in
      // An owned sync consumes its own recovery transition and replacement
      // budget. The signal must not create another retry behind that owner.
      guard syncCoordinator?.isSyncing == false else { return }
      self?.reconcileRecovery()
    }
  }

  /// Auth can finish after bootstrap (for example StoreKit’s update stream).
  /// Reconcile only in a visible scene and merge with its existing work.
  func reconcileRecovery() {
    guard task == nil else { return }
    pendingReconciliation = true
    needsRecovery = true
    guard phase == .active else { return }
    startRecovery()
  }

  private func startRecovery() {
    guard task == nil else { return }
    needsRecovery = false
    pendingReconciliation = false
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
