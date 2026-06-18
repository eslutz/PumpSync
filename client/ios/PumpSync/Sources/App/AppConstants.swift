import Foundation

enum AppConstants {
  static let backgroundTaskIdentifier = "dev.ericslutz.PumpSync.daily-sync"
  static let staleSyncInterval: TimeInterval = 20 * 60 * 60
  static let hostedSubscriptionProductId =
    Bundle.main.object(forInfoDictionaryKey: "HOSTED_SUBSCRIPTION_PRODUCT_ID") as? String
      ?? "dev.ericslutz.PumpSync.hosted.monthly"
  static let defaultAPIBaseURL =
    (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)
      .flatMap(URL.init(string:))
      ?? URL(string: "https://func-pumpsync-nonprod-flex-api.azurewebsites.net/api")!
}
