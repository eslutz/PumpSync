import Foundation

enum AppConstants {
  static let backgroundTaskIdentifier = "dev.ericslutz.PumpSync.daily-sync"
  static let staleSyncInterval: TimeInterval = 20 * 60 * 60
  static let hostedSubscriptionProductId =
    Bundle.main.object(forInfoDictionaryKey: "HOSTED_SUBSCRIPTION_PRODUCT_ID") as? String
      ?? "dev.ericslutz.PumpSync.hosted.monthly"
  static let hostedSubscriptionGroupId =
    Bundle.main.object(forInfoDictionaryKey: "HOSTED_SUBSCRIPTION_GROUP_ID") as? String
      ?? "22168040"
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
