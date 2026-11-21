import Foundation

enum AppConstants {
  static let backgroundTaskIdentifier = "dev.ericslutz.PumpSync.daily-sync"
  /// App-open synchronization uses this freshness target. A system-granted
  /// background task always syncs because another opportunity is not assured.
  static let staleSyncInterval: TimeInterval = 4 * 60 * 60
  static let termsOfUseURL = URL(string: "https://pumpsync.ericslutz.dev/terms/")!
  static let privacyPolicyURL = URL(string: "https://pumpsync.ericslutz.dev/privacy/")!
  static let dataDeletionURL = URL(string: "https://pumpsync.ericslutz.dev/privacy/data-deletion/")!

  /// Only upgrades can have an identifier associated with legacy hosted metadata.
  static func legacyInstallationID(defaults: UserDefaults = .standard) -> String? {
    guard let value = defaults.string(forKey: InstallStateReconciler.legacyInstallationIdKey), UUID(uuidString: value) != nil else { return nil }
    return value
  }
}
