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

#if DEBUG
  static var screenshotPreviewState: String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard isScreenshotMode, let index = arguments.firstIndex(of: "--pumpsync-screenshot-preview"),
          arguments.indices.contains(index + 1) else { return nil }
    let state = arguments[index + 1]
    return ["loading", "empty", "populated"].contains(state) ? state : nil
  }
#endif
}
