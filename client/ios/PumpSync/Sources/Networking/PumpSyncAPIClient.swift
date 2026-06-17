import Foundation

struct PumpSyncAPIClient {
  var baseURL: URL
  var urlSession: URLSession

  static func live() -> PumpSyncAPIClient {
    let configuredBaseURL = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
    let baseURL = configuredBaseURL.flatMap(URL.init(string:)) ?? URL(string: "https://localhost:7071")!
    return PumpSyncAPIClient(baseURL: baseURL, urlSession: .shared)
  }

  func createAppleSession(_ request: AppleSessionRequest) async throws -> AppleSessionResponse {
    try await send(path: "/v1/auth/apple/session", method: "POST", body: request, accessToken: nil)
  }

  func getStatus(accessToken: String) async throws -> StatusResponse {
    try await send(path: "/v1/status", method: "GET", body: EmptyRequest(), accessToken: accessToken)
  }

  func syncTandem(_ request: TandemSyncRequest, accessToken: String) async throws -> TandemSyncResponse {
    try await send(path: "/v1/sync/tandem", method: "POST", body: request, accessToken: accessToken)
  }

  private func send<Request: Encodable, Response: Decodable>(
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
