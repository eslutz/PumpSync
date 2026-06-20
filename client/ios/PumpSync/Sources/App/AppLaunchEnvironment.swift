import Foundation

enum AppLaunchEnvironment {
  static var isScreenshotMode: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-mode")
      || ProcessInfo.processInfo.environment["PUMPSYNC_SCREENSHOT_MODE"] == "1"
  }
}
