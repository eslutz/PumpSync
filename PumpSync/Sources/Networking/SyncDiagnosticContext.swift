import Foundation

/// Categories retained to decode diagnostics recorded by service-backed versions.
enum SyncRequestEndpoint: String, Codable, Sendable {
  case capabilities, challenge, subscriptionSession, selfHostedSession, sessionRefresh, sync, preview, validateCredentials, other
}

struct SyncRequestLink: Codable, Equatable, Sendable {
  let requestID: String
  let endpoint: SyncRequestEndpoint
  var backendCorrelationID: String?
  var traceID: String?
  var responseReceived = false

  static func safeReference(_ value: String?) -> String? {
    guard let value, value.range(of: #"^(?:[0-9A-Z]{13}:[0-9A-F]{8}|[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$"#, options: .regularExpression) != nil else { return nil }
    return value.lowercased()
  }

  static func safeTrace(_ value: String?) -> String? {
    guard let value, value.range(of: #"^[0-9a-fA-F]{32}$"#, options: .regularExpression) != nil else { return nil }
    return value.lowercased()
  }
}
