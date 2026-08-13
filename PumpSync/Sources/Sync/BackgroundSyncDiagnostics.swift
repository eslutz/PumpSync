import Foundation

enum BackgroundRefreshAvailability: String {
  case available
  case denied
  case restricted
  case unknown
}

enum BackgroundSyncDiagnostics {
  static var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }

  static func schedulingContext(
    buildNumber: String,
    refreshStatus: BackgroundRefreshAvailability,
    isLowPowerModeEnabled: Bool
  ) -> String {
    "build=\(buildNumber) refreshStatus=\(refreshStatus.rawValue) lowPowerMode=\(isLowPowerModeEnabled)"
  }

  static func pendingRequestDescription(identifier: String, earliestBeginDate: Date?) -> String {
    let earliest = earliestBeginDate.map(iso8601) ?? "none"
    return "identifier=\(identifier) earliestBeginDate=\(earliest)"
  }

  static func stageDescription(buildNumber: String, stage: String, elapsedMs: Int) -> String {
    "build=\(buildNumber) stage=\(stage) elapsedMs=\(elapsedMs)"
  }

  static func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
