import Foundation
import Observation

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

  func getCapabilities() async throws -> CapabilitiesResponse {
    try await send(path: "/v1/capabilities", method: "GET", body: EmptyRequest(), accessToken: nil)
  }

  func createSubscriptionSession(_ request: SubscriptionSessionRequest) async throws -> BackendSessionResponse {
    try await send(path: "/v1/subscription/session", method: "POST", body: request, accessToken: nil)
  }

  func createSelfHostedSession(_ request: SelfHostedSessionRequest) async throws -> BackendSessionResponse {
    try await send(path: "/v1/self-host/session", method: "POST", body: request, accessToken: nil)
  }

  func getStatus(accessToken: String) async throws -> StatusResponse {
    try await send(path: "/v1/status", method: "GET", body: EmptyRequest(), accessToken: accessToken)
  }

  func syncTandem(_ request: TandemSyncRequest, accessToken: String) async throws -> TandemSyncResponse {
    try await send(path: "/v1/sync/tandem", method: "POST", body: request, accessToken: accessToken)
  }

  func validateTandemCredentials(_ request: TandemCredentialValidationRequest, accessToken: String) async throws -> TandemCredentialValidationResponse {
    try await send(path: "/v1/tandem/credentials/validate", method: "POST", body: request, accessToken: accessToken)
  }

  private func send<Request: Encodable, Response: Decodable>(
    path: String,
    method: String,
    body: Request,
    accessToken: String?
  ) async throws -> Response {
    var lastError: Error?

    for attempt in 0...maxRetryCount {
      do {
        return try await sendOnce(path: path, method: method, body: body, accessToken: accessToken)
      } catch {
        lastError = error
        guard shouldRetry(error: error), attempt < maxRetryCount else {
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
    accessToken: String?
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

    let (data, response) = try await urlSession.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIClientError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let errorResponse = try? JSONCodec.decoder.decode(ErrorResponse.self, from: data)
      throw APIClientError.httpStatus(httpResponse.statusCode, errorResponse?.message)
    }

    return try JSONCodec.decoder.decode(Response.self, from: data)
  }

  private func shouldRetry(error: Error) -> Bool {
    if let apiError = error as? APIClientError {
      return apiError.isTransient
    }

    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain
  }
}

private struct EmptyRequest: Encodable {}

private struct ErrorResponse: Decodable {
  let code: String
  let message: String
  let correlationId: String?
}

enum APIClientError: LocalizedError {
  case invalidResponse
  case httpStatus(Int, String?)

  var isTransient: Bool {
    switch self {
    case .invalidResponse:
      return true
    case .httpStatus(let status, _):
      return status == 408 || status == 429 || (500..<600).contains(status)
    }
  }

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "The server returned an invalid response."
    case .httpStatus(let status, let message):
      return message ?? "The server returned HTTP \(status)."
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

  private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let iso8601: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}
