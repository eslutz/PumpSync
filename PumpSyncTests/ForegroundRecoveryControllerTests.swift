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
}
