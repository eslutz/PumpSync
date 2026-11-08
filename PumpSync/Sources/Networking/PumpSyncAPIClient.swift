import Foundation
import Observation

enum ConnectionTimeouts {
  static let hosted: TimeInterval = 75
  static let selfHosted: TimeInterval = 7

  static func value(for mode: BackendAccessMode) -> TimeInterval {
    switch mode {
    case .hosted: hosted
    case .selfHosted: selfHosted
    }
  }
}

@MainActor
@Observable
final class PumpSyncAPIClient {
  var baseURL: URL
  var urlSession: URLSession
  var maxRetryCount: Int = 2

  init(baseURL: URL, urlSession: URLSession, maxRetryCount: Int = 2) {
    self.baseURL = baseURL
    self.urlSession = urlSession
    self.maxRetryCount = maxRetryCount
  }

  static func live() -> PumpSyncAPIClient {
    let baseURL = AppConstants.defaultAPIBaseURL
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return PumpSyncAPIClient(baseURL: baseURL, urlSession: URLSession(configuration: configuration))
  }

  func updateBaseURL(_ baseURL: URL) {
    self.baseURL = baseURL
  }

  func createSubscriptionSession(_ request: SubscriptionSessionRequest, backendCorrelation: ((String?) -> Void)? = nil) async throws -> BackendSessionResponse {
    try await send(
      path: "/v1/subscription/session", method: "POST", body: request, accessToken: nil,
      allowsRetry: false, timeoutInterval: ConnectionTimeouts.hosted, responseCancellationPolicy: .preserveReceivedResponse,
      responseObserver: { backendCorrelation?($0.value(forHTTPHeaderField: "X-Correlation-ID")) }
    )
  }

  func createSelfHostedSession(_ request: SelfHostedSessionRequest, backendCorrelation: ((String?) -> Void)? = nil) async throws -> BackendSessionResponse {
    try await send(
      path: "/v1/self-host/session", method: "POST", body: request, accessToken: nil,
      allowsRetry: false, timeoutInterval: ConnectionTimeouts.selfHosted, responseCancellationPolicy: .preserveReceivedResponse,
      responseObserver: { backendCorrelation?($0.value(forHTTPHeaderField: "X-Correlation-ID")) }
    )
  }

  func createSessionChallenge(_ request: SessionChallengeRequest) async throws -> SessionChallengeResponse {
    let timeout = request.purpose == "hostedEnrollment" ? ConnectionTimeouts.hosted : ConnectionTimeouts.selfHosted
    return try await send(
      path: "/v1/session/challenge", method: "POST", body: request, accessToken: nil,
      timeoutInterval: timeout
    )
  }

  func refreshSession(_ request: SessionRefreshRequest, mode: BackendAccessMode, backendCorrelation: ((String?) -> Void)? = nil) async throws -> BackendSessionResponse {
    try await send(
      path: "/v1/session/refresh", method: "POST", body: request, accessToken: nil,
      allowsRetry: false, timeoutInterval: ConnectionTimeouts.value(for: mode), responseCancellationPolicy: .preserveReceivedResponse,
      responseObserver: { backendCorrelation?($0.value(forHTTPHeaderField: "X-Correlation-ID")) }
    )
  }

  func syncTandem(_ request: TandemSyncRequest, accessToken: String, backendCorrelation: ((String?) -> Void)? = nil) async throws -> TandemSyncResponse {
    var correlation: String?
    var response: TandemSyncResponse = try await send(path: "/v1/sync/tandem", method: "POST", body: request, accessToken: accessToken, responseObserver: {
      correlation = $0.value(forHTTPHeaderField: "X-Correlation-ID")
      backendCorrelation?(correlation)
    })
    response.backendCorrelationID = correlation
    return response
  }

  func previewTandem(_ request: TandemSyncRequest, accessToken: String) async throws -> TandemSyncResponse {
    try await send(path: "/v1/preview/tandem", method: "POST", body: request, accessToken: accessToken)
  }

  func capabilities() async throws -> BackendCapabilitiesResponse {
    try await send(path: "/v1/capabilities", method: "GET", body: EmptyAPIRequest(), accessToken: nil)
  }

  func validateTandemCredentials(_ request: TandemCredentialValidationRequest, accessToken: String) async throws -> TandemCredentialValidationResponse {
    try await send(path: "/v1/tandem/credentials/validate", method: "POST", body: request, accessToken: accessToken)
  }

  /// Starts hosted Container Apps activation without requiring an authenticated
  /// operation. This GET is safe to retry once because it does not create or
  /// mutate authentication state.
  func warmup() async throws {
    let session = urlSession
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/capabilities"))
    request.httpMethod = "GET"
    request.timeoutInterval = ConnectionTimeouts.hosted
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    for attempt in 0...1 {
      let link = SyncDiagnosticContext.prepare(&request, path: "/v1/capabilities")
      do {
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
          throw APIClientError.invalidResponse
        }
        SyncDiagnosticContext.received(response, link: link)
        guard (200..<300).contains(response.statusCode) else {
          throw APIClientError.httpStatus(response.statusCode, code: nil, message: nil)
        }
        return
      } catch {
        guard attempt == 0, shouldRetryWarmup(error: error) else {
          throw error
        }
        try await Task.sleep(for: .milliseconds(250))
      }
    }
  }

  private func send<Request: Encodable, Response: Decodable & Sendable>(
    path: String,
    method: String,
    body: Request,
    accessToken: String?,
    allowsRetry: Bool = true,
    timeoutInterval: TimeInterval? = nil,
    responseCancellationPolicy: APIResponseCancellationPolicy = .cancelWhenRequested,
    responseObserver: ((HTTPURLResponse) -> Void)? = nil
  ) async throws -> Response {
    var lastError: Error?
    // All retries belong to the same connection. A settings change may replace
    // the client's configuration while URLSession is suspended.
    let configuration = RequestConfiguration(
      baseURL: baseURL, session: urlSession, retryCount: max(0, maxRetryCount),
      timeout: timeoutInterval ?? self.timeoutInterval(for: path),
      responseCancellationPolicy: responseCancellationPolicy
    )
    let encodedBody = method == "GET" ? nil : try NativePerformance.measure("Encode API request") {
      try JSONCodec.encoder.encode(body)
    }

    for attempt in 0...configuration.retryCount {
      do {
        return try await sendOnce(
          configuration: configuration, path: path, method: method, body: encodedBody, accessToken: accessToken,
          responseObserver: responseObserver
        )
      } catch {
        lastError = error
        guard allowsRetry, shouldRetry(error: error), attempt < configuration.retryCount else {
          throw error
        }

        try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
      }
    }

    throw lastError ?? APIClientError.invalidResponse
  }

  private struct RequestConfiguration {
    let baseURL: URL
    let session: URLSession
    let retryCount: Int
    let timeout: TimeInterval
    let responseCancellationPolicy: APIResponseCancellationPolicy
  }

  private func sendOnce<Response: Decodable & Sendable>(
    configuration: RequestConfiguration,
    path: String,
    method: String,
    body: Data?,
    accessToken: String?,
    responseObserver: ((HTTPURLResponse) -> Void)?
  ) async throws -> Response {
    var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    urlRequest.httpMethod = method
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    if let body {
      urlRequest.httpBody = body
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    if let accessToken {
      urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    urlRequest.timeoutInterval = configuration.timeout
    let link = SyncDiagnosticContext.prepare(&urlRequest, path: path)
    let download = NativePerformance.begin("Download API response")
    let (data, response): (Data, URLResponse)
    do {
      defer { NativePerformance.end("Download API response", download) }
      (data, response) = try await configuration.session.data(for: urlRequest, delegate: SensitiveRequestRedirectGuard())
    }
    try configuration.responseCancellationPolicy.checkCancellation()
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIClientError.invalidResponse
    }

    SyncDiagnosticContext.received(httpResponse, link: link)
    responseObserver?(httpResponse)
    guard (200..<300).contains(httpResponse.statusCode) else {
      let errorResponse = try? await APIResponseDecoder.decode(ErrorResponse.self, from: data,
        cancellationPolicy: configuration.responseCancellationPolicy)
      try configuration.responseCancellationPolicy.checkCancellation()
      throw APIClientError.httpStatus(
        httpResponse.statusCode,
        code: errorResponse?.code,
        message: errorResponse?.message,
        correlationId: errorResponse?.correlationId ?? httpResponse.value(forHTTPHeaderField: "X-Correlation-ID")
      )
    }

    return try await APIResponseDecoder.decode(Response.self, from: data,
      cancellationPolicy: configuration.responseCancellationPolicy)
  }

  private func timeoutInterval(for path: String) -> TimeInterval {
    if (path.contains("sync/tandem") || path.contains("preview/tandem")) || path.contains("tandem/credentials/validate") {
      return 120
    }

    return 60
  }

  /// Every request this client sends is a POST, and two of them carry the
  /// user's Tandem credentials — a retry re-transmits those and can trigger a
  /// second backend Tandem login. Retry only URL errors where the request
  /// clearly never reached the server; notably NOT `.timedOut`, where the
  /// original request may already have been delivered and processed.
  private static let retryableURLErrorCodes: Set<Int> = [
    NSURLErrorCannotConnectToHost,
    NSURLErrorCannotFindHost,
    NSURLErrorDNSLookupFailed,
    NSURLErrorNetworkConnectionLost
  ]

  private func shouldRetry(error: Error) -> Bool {
    if let apiError = error as? APIClientError {
      return apiError.isTransient
    }

    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && Self.retryableURLErrorCodes.contains(nsError.code)
  }

  private func shouldRetryWarmup(error: Error) -> Bool {
    if let apiError = error as? APIClientError {
      return apiError.isTransient
    }

    let error = error as NSError
    return error.domain == NSURLErrorDomain && (
      error.code == NSURLErrorTimedOut || Self.retryableURLErrorCodes.contains(error.code)
    )
  }
}

private struct ErrorResponse: Decodable, Sendable {
  let code: String
  let message: String
  let correlationId: String?
}

enum APIClientError: LocalizedError {
  case invalidResponse
  case httpStatus(Int, code: String?, message: String?, correlationId: String? = nil)

  var backendCode: String? {
    guard case .httpStatus(_, let code, _, _) = self else { return nil }
    return code
  }

  var correlationId: String? {
    guard case .httpStatus(_, _, _, let correlationId) = self else { return nil }
    return correlationId
  }

  var isDeviceProofRejected: Bool {
    guard case .httpStatus(401, let code, _, _) = self else { return false }
    return code == "device_proof_rejected"
  }

  var isDeviceEnrollmentRequired: Bool {
    guard case .httpStatus(401, let code, _, _) = self else { return false }
    return code == "device_enrollment_required"
  }

  var isDeviceKeyReenrollmentRequired: Bool {
    guard case .httpStatus(401, let code, _, _) = self else { return false }
    return code == "device_key_reenrollment_required"
  }

  var isAuthenticationFailure: Bool {
    switch self {
    case .invalidResponse:
      return false
    case .httpStatus(let status, _, _, _):
      return status == 401 || status == 403
    }
  }

  var isActiveSubscriptionRequired: Bool {
    guard case .httpStatus(401, let code, _, _) = self else { return false }
    return code == "active_subscription_required"
  }

  var hasAmbiguousOutcome: Bool {
    switch self {
    case .invalidResponse:
      return true
    case .httpStatus(let status, _, _, _):
      return status == 408 || status >= 500
    }
  }

  /// 424: the backend reached Tandem Source but Tandem rejected the stored
  /// pump credentials — the remedy is re-saving the Tandem account, not
  /// retrying or reconnecting PumpSync.
  var isTandemCredentialFailure: Bool {
    if case .httpStatus(424, _, _, _) = self {
      return true
    }

    return false
  }

  var isRateLimited: Bool {
    if case .httpStatus(429, _, _, _) = self {
      return true
    }

    return false
  }

  var isTransient: Bool {
    switch self {
    case .invalidResponse:
      return true
    case .httpStatus(let status, let code, _, _):
      if code == "tandem_source_request_rejected" { return false }
      // 429 is deliberately NOT transient: the backend's rate-limit windows
      // are minutes to an hour, so a sub-second retry is guaranteed to fail
      // and just consumes more budget. Callers surface a wait message.
      return status == 408 || (500..<600).contains(status)
    }
  }

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "The server returned an invalid response."
    case .httpStatus(let status, _, let message, let correlationId):
      let base = message ?? "The server returned HTTP \(status)."
      guard let correlationId, !correlationId.isEmpty else {
        return base
      }
      return "\(base) Reference: \(correlationId)."
    }
  }
}

private struct EmptyAPIRequest: Encodable {}

struct BackendCapabilitiesResponse: Decodable, Sendable {
  let dataSourceMode: DataSourceMode
  let supportsImportPreview: Bool
  private enum CodingKeys: String, CodingKey { case dataSourceMode, supportsImportPreview }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    dataSourceMode = try values.decodeIfPresent(DataSourceMode.self, forKey: .dataSourceMode) ?? .unknown
    supportsImportPreview = try values.decodeIfPresent(Bool.self, forKey: .supportsImportPreview) ?? false
  }
}

/// Protected requests never forward credentials or bearer tokens through redirects.
final class SensitiveRequestRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
    nil
  }
}
