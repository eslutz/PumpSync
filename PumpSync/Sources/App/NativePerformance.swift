import Foundation
import OSLog

/// Static signpost names only: never includes payloads, endpoints, account
/// identifiers, tokens, health measurements, or arbitrary error descriptions.
enum NativePerformance {
  private static let signposter = OSSignposter(subsystem: "dev.ericslutz.PumpSync", category: "Performance")
  private static let logger = Logger(subsystem: "dev.ericslutz.PumpSync", category: "Lifecycle")

  static func begin(_ name: StaticString) -> OSSignpostIntervalState {
    signposter.beginInterval(name, id: signposter.makeSignpostID())
  }

  static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
    signposter.endInterval(name, state)
  }

  static func measure<Value>(_ name: StaticString, operation: () throws -> Value) rethrows -> Value {
    let interval = begin(name)
    defer { end(name, interval) }
    return try operation()
  }

  static func metricCollectorStarted(modern: Bool) {
    if modern {
      logger.info("Started native async MetricKit collection")
    } else {
      logger.info("Started native legacy MetricKit collection")
    }
  }
}
