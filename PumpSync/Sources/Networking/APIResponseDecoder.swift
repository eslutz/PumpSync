import Foundation

enum APIResponseCancellationPolicy: Sendable {
  case cancelWhenRequested
  // A consuming authentication POST may have rotated server credentials. Once
  // its bytes arrive, the auth owner must journal the response (or definitive
  // rejection), even if the waiting UI or background task has been cancelled.
  case preserveReceivedResponse

  func checkCancellation() throws {
    if self == .cancelWhenRequested { try Task.checkCancellation() }
  }
}

/// Large import responses must not occupy the UI executor. Only immutable data
/// and explicitly Sendable decoded values cross this boundary.
enum APIResponseDecoder {
  @concurrent
  static func decode<Response: Decodable & Sendable>(
    _ type: Response.Type, from data: Data,
    cancellationPolicy: APIResponseCancellationPolicy = .cancelWhenRequested
  ) async throws -> Response {
    try cancellationPolicy.checkCancellation()
    let response = try NativePerformance.measure("Decode API response") {
      try JSONCodec.decoder.decode(type, from: data)
    }
    try cancellationPolicy.checkCancellation()
    return response
  }
}
