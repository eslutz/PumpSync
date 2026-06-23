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
  static let defaultAPIBaseURL =
    (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)
      .flatMap(URL.init(string:))
      ?? URL(string: "https://ca-pumpsync-nonprod-api.gentlesea-b1e8a783.eastus2.azurecontainerapps.io/api")!
}
