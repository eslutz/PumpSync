import Foundation

/// Allowlisted request categories; raw URLs and payloads never enter diagnostics.
enum SyncRequestEndpoint: String, Codable, Sendable {
  case capabilities, challenge, subscriptionSession, selfHostedSession, sessionRefresh, sync, preview, validateCredentials, other

  init(path: String) {
    switch path {
    case "/v1/capabilities": self = .capabilities
    case "/v1/session/challenge": self = .challenge
    case "/v1/subscription/session": self = .subscriptionSession
    case "/v1/self-host/session": self = .selfHostedSession
    case "/v1/session/refresh": self = .sessionRefresh
    case "/v1/sync/tandem": self = .sync
    case "/v1/preview/tandem": self = .preview
    case "/v1/tandem/credentials/validate": self = .validateCredentials
    default: self = .other
    }
  }
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

struct SyncDiagnosticContext: Sendable {
  let operationID: UUID
  let trigger: SyncTriggerReason
  let record: @MainActor @Sendable (SyncRequestLink) -> Void
  var recordDropped: @MainActor @Sendable (Int) -> Void = { _ in }

  @TaskLocal static var current: SyncDiagnosticContext?

  @MainActor
  static func prepare(_ request: inout URLRequest, path: String) -> SyncRequestLink {
    let requestID = UUID().uuidString.lowercased()
    request.setValue(requestID, forHTTPHeaderField: "X-Correlation-ID")
    if let current {
      request.setValue(current.operationID.uuidString.lowercased(), forHTTPHeaderField: "X-Client-Operation-ID")
      request.setValue(current.trigger.rawValue, forHTTPHeaderField: "X-Client-Sync-Trigger")
    }
    let link = SyncRequestLink(requestID: requestID, endpoint: SyncRequestEndpoint(path: path))
    current?.record(link)
    SessionRecoveryContext.current?.recordRequestLink(link)
    return link
  }

  @MainActor
  static func received(_ response: HTTPURLResponse, link: SyncRequestLink) {
    var completed = link
    completed.backendCorrelationID = SyncRequestLink.safeReference(response.value(forHTTPHeaderField: "X-Correlation-ID"))
    completed.traceID = SyncRequestLink.safeTrace(response.value(forHTTPHeaderField: "X-Trace-ID"))
    completed.responseReceived = true
    current?.record(completed)
    SessionRecoveryContext.current?.recordRequestLink(completed)
  }
}
