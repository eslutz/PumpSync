import Foundation

enum AppLaunchEnvironment {
  static var isScreenshotMode: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-mode")
      || ProcessInfo.processInfo.environment["PUMPSYNC_SCREENSHOT_MODE"] == "1"
  }

  static var isScreenshotSyncing: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-syncing")
  }

  static var isScreenshotSyncSuccess: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-sync-success")
  }

  static var isScreenshotSyncFailure: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-sync-failure")
  }

  static var isScreenshotInitialSync: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-initial-sync")
  }
}
