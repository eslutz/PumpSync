import Synchronization
import XCTest
@testable import PumpSync

final class BackgroundExecutionDeadlineTests: XCTestCase {
  func testCancellationCannotBeReportedAsCompletedByPollingWorker() async {
    for attempt in 0..<100 {
      let started = expectation(description: "Polling operation started \(attempt)")
      let caller = Task {
        await BackgroundExecutionDeadline.run(timeout: .seconds(3)) {
          let pollingDeadline = Date().addingTimeInterval(1)
          started.fulfill()
          while !Task.isCancelled, Date() < pollingDeadline {}
          return false
        }
      }
      await fulfillment(of: [started], timeout: 1)

      caller.cancel()

      let outcome = await caller.value
      XCTAssertEqual(outcome, .cancelled, "Polling cancellation attempt \(attempt)")
    }
  }

  func testCompletedResultsArePreserved() async {
    for result in [true, false] {
      let lease = SyncExecutionLease(kind: .background, deadline: Date().addingTimeInterval(3))
      let outcome = await BackgroundExecutionDeadline.run(timeout: .seconds(3), lease: lease) { result }

      XCTAssertEqual(outcome, .completed(result))
      XCTAssertFalse(lease.isValid)
    }
  }

  func testAlreadyCancelledCallerDoesNotStartOperation() async {
    let operationStarted = Mutex(false)
    let lease = SyncExecutionLease(kind: .background, deadline: Date().addingTimeInterval(3))
    let caller = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await BackgroundExecutionDeadline.run(timeout: .seconds(3), lease: lease) {
        operationStarted.withLock { $0 = true }
        return true
      }
    }

    let outcome = await caller.value
    XCTAssertEqual(outcome, .cancelled)
    XCTAssertFalse(operationStarted.withLock { $0 })
    XCTAssertFalse(lease.isValid)
  }

  func testCancellationWinsOverCooperativeCompletion() async {
    for attempt in 0..<100 {
      let started = expectation(description: "Operation started \(attempt)")
      let caller = Task {
        await BackgroundExecutionDeadline.run(timeout: .seconds(3)) {
          started.fulfill()
          do {
            try await Task.sleep(for: .seconds(60))
            return true
          } catch {
            return false
          }
        }
      }
      await fulfillment(of: [started], timeout: 1)

      caller.cancel()

      let outcome = await caller.value
      XCTAssertEqual(outcome, .cancelled, "Cancellation attempt \(attempt)")
    }
  }

  func testTimeoutWinsOverCooperativeCompletion() async {
    for attempt in 0..<32 {
      let outcome = await BackgroundExecutionDeadline.run(timeout: .milliseconds(1)) {
        do {
          try await Task.sleep(for: .seconds(60))
          return true
        } catch {
          return false
        }
      }

      XCTAssertEqual(outcome, .timedOut, "Timeout attempt \(attempt)")
    }
  }

  func testCancellingCallerCancelsOperationBeforeDeadline() async {
    let operationStarted = Mutex(false)
    let cancellationObserved = Mutex(false)
    let lease = SyncExecutionLease(kind: .background, deadline: Date().addingTimeInterval(3))
    let caller = Task {
      await BackgroundExecutionDeadline.run(timeout: .seconds(3), lease: lease) {
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
    XCTAssertFalse(lease.isValid, "The system expiration cancellation path revokes the grant immediately")
    let cancellationDeadline = Date().addingTimeInterval(1)
    while !cancellationObserved.withLock({ $0 }), Date() < cancellationDeadline {
      await Task.yield()
    }
    XCTAssertTrue(cancellationObserved.withLock { $0 })
  }

  func testDeadlineReturnsFailureAndCancelsStalledOperation() async {
    let cancellationObserved = Mutex(false)
    let lease = SyncExecutionLease(kind: .background, deadline: Date().addingTimeInterval(3))

    let outcome = await BackgroundExecutionDeadline.run(timeout: .milliseconds(50), lease: lease) {
      do {
        try await Task.sleep(for: .seconds(60))
        return true
      } catch {
        cancellationObserved.withLock { $0 = true }
        return false
      }
    }

    XCTAssertEqual(outcome, .timedOut)
    XCTAssertFalse(lease.isValid)
    let cancellationDeadline = Date().addingTimeInterval(1)
    while !cancellationObserved.withLock({ $0 }), Date() < cancellationDeadline {
      await Task.yield()
    }
    XCTAssertTrue(cancellationObserved.withLock { $0 })
  }
}
