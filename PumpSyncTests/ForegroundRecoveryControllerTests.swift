import SwiftUI
import XCTest
@testable import PumpSync

@MainActor
final class ForegroundRecoveryControllerTests: XCTestCase {
  func testInactiveDoesNotRestartOrCancelRecoveryAndBackgroundDoesCancel() async {
    var attempts = 0
    var cancellationObserved = false
    var visibility: [Bool] = []
    let controller = ForegroundRecoveryController(setVisible: { visibility.append($0) }) {
      attempts += 1
      do { try await Task.sleep(for: .seconds(60)) }
      catch { cancellationObserved = true }
    }
    controller.setScenePhase(.inactive)
    controller.setScenePhase(.active)
    let deadline = Date().addingTimeInterval(1)
    while attempts == 0, Date() < deadline { await Task.yield() }
    controller.setScenePhase(.inactive)
    controller.setScenePhase(.active)
    controller.retryConnection()
    await Task.yield()
    XCTAssertEqual(attempts, 1)
    XCTAssertFalse(cancellationObserved)
    controller.setScenePhase(.background)
    let cancellationDeadline = Date().addingTimeInterval(1)
    while !cancellationObserved, Date() < cancellationDeadline { await Task.yield() }
    XCTAssertTrue(cancellationObserved)
    XCTAssertEqual(visibility, [true, true, true, true, false])
  }

  func testRetryOnlyRunsWhileVisibleAndDoesNotRetryAutomatically() async {
    var attempts = 0
    let controller = ForegroundRecoveryController(setVisible: { _ in }) { attempts += 1 }
    controller.retryConnection()
    await Task.yield()
    XCTAssertEqual(attempts, 0)
    controller.setScenePhase(.active)
    let firstDeadline = Date().addingTimeInterval(1)
    while attempts == 0, Date() < firstDeadline { await Task.yield() }
    for _ in 0..<10 { await Task.yield() }
    controller.setScenePhase(.inactive)
    controller.setScenePhase(.active)
    await Task.yield()
    XCTAssertEqual(attempts, 1)
    controller.retryConnection()
    let retryDeadline = Date().addingTimeInterval(1)
    while attempts < 2, Date() < retryDeadline { await Task.yield() }
    XCTAssertEqual(attempts, 2)
  }
  func testReconciliationMergesExistingRecoveryAndWaitsForNextActiveScene() async {
    var attempts = 0
    var continuation: CheckedContinuation<Void, Never>?
    let controller = ForegroundRecoveryController(setVisible: { _ in }) {
      attempts += 1
      if attempts == 1 { await withCheckedContinuation { continuation = $0 } }
    }
    controller.reconcileRecovery()
    await Task.yield()
    XCTAssertEqual(attempts, 0)
    controller.setScenePhase(.active)
    await waitUntil { continuation != nil }
    controller.reconcileRecovery()
    controller.reconcileRecovery()
    await Task.yield()
    XCTAssertEqual(attempts, 1)
    continuation?.resume()
    await waitUntil { !controller.isRecovering }
    controller.reconcileRecovery()
    await waitUntil { !controller.isRecovering }
    XCTAssertEqual(attempts, 2)
    controller.setScenePhase(.background)
    controller.reconcileRecovery()
    await Task.yield()
    XCTAssertEqual(attempts, 2)
    controller.setScenePhase(.active)
    await waitUntil { !controller.isRecovering }
    XCTAssertEqual(attempts, 3)
  }

  private func waitUntil(_ predicate: () -> Bool) async {
    let deadline = Date().addingTimeInterval(1)
    while !predicate(), Date() < deadline { await Task.yield() }
    XCTAssertTrue(predicate())
  }

  func testBackgroundClosedPreviewReturnDoesNotRecoverForEitherDismissalOrder() async {
    for dismissalBeforeActivation in [true, false] {
      var attempts = 0
      var previewActive = false
      let controller = ForegroundRecoveryController(setVisible: { _ in }) {
        guard !previewActive else { return }
        attempts += 1
      }
      controller.setScenePhase(.active)
      await waitUntil { attempts == 1 && !controller.isRecovering }
      previewActive = true
      controller.setPreviewActive(true)
      controller.previewClosedInBackground()
      controller.setScenePhase(.background)
      if dismissalBeforeActivation {
        previewActive = false
        controller.setPreviewActive(false)
      }
      controller.setScenePhase(.active)
      XCTAssertFalse(controller.isRecovering, "The preview return cannot acquire a new recovery owner")
      await waitUntil { !controller.isRecovering }
      if !dismissalBeforeActivation {
        previewActive = false
        controller.setPreviewActive(false)
      }
      for _ in 0..<10 { await Task.yield() }
      XCTAssertEqual(attempts, 1, "Returning from a background-closed preview must not start recovery; dismissBeforeActive=\(dismissalBeforeActivation)")

      controller.retryConnection()
      await waitUntil { !controller.isRecovering }
      XCTAssertEqual(attempts, 2, "An explicit retry remains eligible")
      controller.reconcileRecovery()
      await waitUntil { !controller.isRecovering }
      XCTAssertEqual(attempts, 3, "A committed auth signal remains eligible")
      controller.setScenePhase(.background)
      controller.setScenePhase(.active)
      await waitUntil { !controller.isRecovering }
      XCTAssertEqual(attempts, 4, "The next ordinary activation still recovers")
    }
  }

  func testConfirmedAuthReconciliationWhileBackgroundedPreviewDrainsAfterBothActivationAndDismissal() async {
    for dismissalBeforeActivation in [true, false] {
      var attempts = 0
      var previewActive = false
      let controller = ForegroundRecoveryController(setVisible: { _ in }) {
        guard !previewActive else { return }
        attempts += 1
      }
      controller.setScenePhase(.active)
      await waitUntil { attempts == 1 && !controller.isRecovering }
      previewActive = true
      controller.setPreviewActive(true)
      controller.previewClosedInBackground()
      controller.setScenePhase(.background)
      controller.reconcileRecovery()
      controller.reconcileRecovery()
      await Task.yield()
      XCTAssertEqual(attempts, 1)
      XCTAssertFalse(controller.isRecovering, "A background auth signal cannot acquire foreground execution")
      if dismissalBeforeActivation {
        previewActive = false
        controller.setPreviewActive(false)
      }
      controller.setScenePhase(.active)
      if !dismissalBeforeActivation {
        XCTAssertFalse(controller.isRecovering, "Auth reconciliation must wait for the actual preview lease release")
        previewActive = false
        controller.setPreviewActive(false)
      }
      await waitUntil { attempts == 2 && !controller.isRecovering }
      for _ in 0..<10 { await Task.yield() }
      XCTAssertEqual(attempts, 2, "Repeated signals drain as one eligible foreground owner")
    }
  }

}
