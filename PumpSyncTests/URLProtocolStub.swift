import Foundation

/// A minimal URLProtocol stub for exercising PumpSyncAPIClient against
/// canned HTTP responses instead of a real network call. Install into a
/// URLSessionConfiguration's protocolClasses and set requestHandler before
/// each request; PumpSyncAPIClient itself is otherwise unmodified.
final class URLProtocolStub: URLProtocol {
  // URLSession invokes URLProtocol callbacks on a background thread it
  // manages internally, not on the caller's actor, so this can't be
  // actor-isolated. Tests only ever set it once (synchronously, before
  // issuing the request that reads it), so there's no real concurrent
  // mutation despite the compiler being unable to verify that.
  nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let handler = URLProtocolStub.requestHandler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
