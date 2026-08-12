import Foundation

enum AppConstants {
  static let backgroundTaskIdentifier = "dev.ericslutz.PumpSync.daily-sync"
  /// Background execution is system-scheduled, so this is a freshness target,
  /// not a guarantee that iOS will wake the app every four hours.
  static let staleSyncInterval: TimeInterval = 4 * 60 * 60
  static let subscriptionProductId =
    Bundle.main.object(forInfoDictionaryKey: "SUBSCRIPTION_PRODUCT_ID") as? String
      ?? "dev.ericslutz.PumpSync.subscription.monthly"
  static let subscriptionGroupId =
    Bundle.main.object(forInfoDictionaryKey: "SUBSCRIPTION_GROUP_ID") as? String
      ?? "22168040"
  // Published policy pages on the public website. App Review guideline 3.1.2
  // requires functional Terms of Use and Privacy Policy links on the
  // subscription purchase screen; these back the paywall's policy
  // destinations. The website is the canonical source for this text, so the
  // app links out rather than carrying a copy (see AGENTS.md).
  static let termsOfUseURL = URL(string: "https://pumpsync.ericslutz.dev/terms/")!
  static let privacyPolicyURL = URL(string: "https://pumpsync.ericslutz.dev/privacy/")!
  // Fail fast rather than fall back: a silent default here could point a
  // misconfigured Release build at the wrong backend environment. The key is
  // injected per configuration from project.yml, so any build missing it is
  // broken at build-configuration level and should crash immediately in
  // development/CI, not limp along against a hardcoded URL.
  static let defaultAPIBaseURL: URL = {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
      let url = URL(string: value),
      url.scheme != nil
    else {
      fatalError("API_BASE_URL is missing or invalid in Info.plist — regenerate the project from project.yml.")
    }

    return url
  }()
}
