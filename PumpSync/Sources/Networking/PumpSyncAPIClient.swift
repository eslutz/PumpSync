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
    return PumpSyncAPIClient(baseURL: baseURL, urlSession: .shared)
  }

  func updateBaseURL(_ baseURL: URL) {
    self.baseURL = baseURL
  }

  func createSubscriptionSession(_ request: SubscriptionSessionRequest) async throws -> BackendSessionResponse {
    try await send(
      path: "/v1/subscription/session", method: "POST", body: request, accessToken: nil,
      allowsRetry: false, timeoutInterval: ConnectionTimeouts.hosted
    )
  }

  func createSelfHostedSession(_ request: SelfHostedSessionRequest) async throws -> BackendSessionResponse {
    try await send(
      path: "/v1/self-host/session", method: "POST", body: request, accessToken: nil,
      allowsRetry: false, timeoutInterval: ConnectionTimeouts.selfHosted
    )
  }

  func createSessionChallenge(_ request: SessionChallengeRequest) async throws -> SessionChallengeResponse {
    let timeout = request.purpose == "hostedEnrollment" ? ConnectionTimeouts.hosted : ConnectionTimeouts.selfHosted
    return try await send(
      path: "/v1/session/challenge", method: "POST", body: request, accessToken: nil,
      timeoutInterval: timeout
    )
  }

  func refreshSession(_ request: SessionRefreshRequest, mode: BackendAccessMode) async throws -> BackendSessionResponse {
    try await send(
      path: "/v1/session/refresh", method: "POST", body: request, accessToken: nil,
      allowsRetry: false, timeoutInterval: ConnectionTimeouts.value(for: mode)
    )
  }

  func syncTandem(_ request: TandemSyncRequest, accessToken: String) async throws -> TandemSyncResponse {
    try await send(path: "/v1/sync/tandem", method: "POST", body: request, accessToken: accessToken)
  }

  func validateTandemCredentials(_ request: TandemCredentialValidationRequest, accessToken: String) async throws -> TandemCredentialValidationResponse {
    try await send(path: "/v1/tandem/credentials/validate", method: "POST", body: request, accessToken: accessToken)
  }

  /// Starts hosted Container Apps activation without requiring an authenticated
  /// operation. This GET is safe to retry once because it does not create or
  /// mutate authentication state.
  func warmup() async throws {
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/capabilities"))
    request.httpMethod = "GET"
    request.timeoutInterval = ConnectionTimeouts.hosted
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    for attempt in 0...1 {
      do {
        let (_, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
          throw APIClientError.invalidResponse
        }
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

  private func send<Request: Encodable, Response: Decodable>(
    path: String,
    method: String,
    body: Request,
    accessToken: String?,
    allowsRetry: Bool = true,
    timeoutInterval: TimeInterval? = nil
  ) async throws -> Response {
    var lastError: Error?

    for attempt in 0...maxRetryCount {
      do {
        return try await sendOnce(
          path: path, method: method, body: body, accessToken: accessToken,
          timeoutInterval: timeoutInterval
        )
      } catch {
        lastError = error
        guard allowsRetry, shouldRetry(error: error), attempt < maxRetryCount else {
          throw error
        }

        try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
      }
    }

    throw lastError ?? APIClientError.invalidResponse
  }

  private func sendOnce<Request: Encodable, Response: Decodable>(
    path: String,
    method: String,
    body: Request,
    accessToken: String?,
    timeoutInterval: TimeInterval?
  ) async throws -> Response {
    var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    urlRequest.httpMethod = method
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    if method != "GET" {
      urlRequest.httpBody = try JSONCodec.encoder.encode(body)
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    if let accessToken {
      urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    urlRequest.timeoutInterval = timeoutInterval ?? self.timeoutInterval(for: path)
    let (data, response) = try await urlSession.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let errorResponse = try? JSONCodec.decoder.decode(ErrorResponse.self, from: data)
      throw APIClientError.httpStatus(
        httpResponse.statusCode,
        code: errorResponse?.code,
        message: errorResponse?.message,
        correlationId: errorResponse?.correlationId ?? httpResponse.value(forHTTPHeaderField: "X-Correlation-ID")
      )
    }

    return try JSONCodec.decoder.decode(Response.self, from: data)
  }

  private func timeoutInterval(for path: String) -> TimeInterval {
    if path.contains("sync/tandem") || path.contains("tandem/credentials/validate") {
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

private struct ErrorResponse: Decodable {
  let code: String
  let message: String
  let correlationId: String?
}

enum APIClientError: LocalizedError {
  case invalidResponse
  case httpStatus(Int, code: String?, message: String?, correlationId: String? = nil)

  var isAuthenticationFailure: Bool {
    switch self {
    case .invalidResponse:
      return false
    case .httpStatus(let status, _, _, _):
      return status == 401 || status == 403
    }
  }

  var hasAmbiguousOutcome: Bool {
    if case .invalidResponse = self { return true }
    return false
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
    case .httpStatus(let status, _, _, _):
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

enum JSONCodec {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)

      if let date = iso8601WithFractionalSeconds.date(from: value) {
        return date
      }

      if let date = iso8601.date(from: value) {
        return date
      }

      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
    }
    return decoder
  }()

  // ISO8601DateFormatter isn't Sendable, but these are configured once here
  // and only ever used for read-only `.date(from:)` calls afterward, which is
  // safe to share across threads in practice.
  private nonisolated(unsafe) static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
