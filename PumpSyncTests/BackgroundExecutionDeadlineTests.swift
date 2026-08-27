import Synchronization
import XCTest
@testable import PumpSync

final class BackgroundExecutionDeadlineTests: XCTestCase {
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
