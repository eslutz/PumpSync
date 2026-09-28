import Synchronization
import XCTest
@testable import PumpSync

final class BackgroundExecutionDeadlineTests: XCTestCase {
  func testCancellingCallerCancelsOperationBeforeDeadline() async {
    let operationStarted = Mutex(false)
    let cancellationObserved = Mutex(false)
    let caller = Task {
      await BackgroundExecutionDeadline.run(timeout: .seconds(3)) {
        operationStarted.withLock { $0 = true }
        do {
          try await Task.sleep(for: .seconds(60))
          return true
        } catch {
          cancellationObserved.withLock { $0 = true }
          return false
        }
      }
    }

    let startDeadline = Date().addingTimeInterval(1)
    while !operationStarted.withLock({ $0 }), Date() < startDeadline {
      await Task.yield()
    }
    XCTAssertTrue(operationStarted.withLock { $0 })

    caller.cancel()

    let outcome = await caller.value
    XCTAssertEqual(outcome, .cancelled)
    let cancellationDeadline = Date().addingTimeInterval(1)
    while !cancellationObserved.withLock({ $0 }), Date() < cancellationDeadline {
      await Task.yield()
    }
    XCTAssertTrue(cancellationObserved.withLock { $0 })
  }

  func testDeadlineReturnsFailureAndCancelsStalledOperation() async {
    let cancellationObserved = Mutex(false)

    let outcome = await BackgroundExecutionDeadline.run(timeout: .milliseconds(50)) {
      do {
        try await Task.sleep(for: .seconds(60))
        return true
      } catch {
        cancellationObserved.withLock { $0 = true }
        return false
      }
    }

    XCTAssertEqual(outcome, .timedOut)
    let cancellationDeadline = Date().addingTimeInterval(1)
    while !cancellationObserved.withLock({ $0 }), Date() < cancellationDeadline {
      await Task.yield()
    }
    XCTAssertTrue(cancellationObserved.withLock { $0 })
  }
}
