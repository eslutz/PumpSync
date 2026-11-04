import Foundation

enum AppLaunchEnvironment {
  static var isScreenshotMode: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-mode")
      || ProcessInfo.processInfo.environment["PUMPSYNC_SCREENSHOT_MODE"] == "1"
  }

  static var isScreenshotSyncing: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-syncing")
  }

  static var isScreenshotSyncSuccess: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-sync-success")
  }

  static var isScreenshotSyncFailure: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-sync-failure")
  }

  static var isScreenshotInitialSync: Bool {
    ProcessInfo.processInfo.arguments.contains("--pumpsync-screenshot-initial-sync")
  }

#if DEBUG
  static var screenshotPreviewState: String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard isScreenshotMode, let index = arguments.firstIndex(of: "--pumpsync-screenshot-preview"),
          arguments.indices.contains(index + 1) else { return nil }
    let state = arguments[index + 1]
    return ["loading", "empty", "populated"].contains(state) ? state : nil
  }
#endif
}

#if DEBUG
/// Intercepts every request in the opt-in preview fixture; none reaches a server.
final class ScreenshotPreviewURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else { return }
    let arguments = ProcessInfo.processInfo.arguments
    let state = arguments.firstIndex(of: "--pumpsync-screenshot-preview")
      .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    let body: String
    if url.path.hasSuffix("/v1/capabilities") {
      body = #"{"dataSourceMode":"tandemSource","supportsImportPreview":true}"#
    } else if url.path.hasSuffix("/v1/preview/tandem") {
      if state == "loading" { return }
      let samples = state == "empty" ? "[]" : #"[{"externalId":"fixture-basal","type":"insulin.basal","value":0.25,"unit":"IU","startAt":"2026-10-05T00:00:00Z","endAt":"2026-10-05T00:30:00Z","metadata":{},"source":{"deviceId":"Synthetic pump","eventIds":["fixture-basal"]}},{"externalId":"fixture-bolus","type":"insulin.bolus","value":1.2,"unit":"IU","startAt":"2026-10-05T00:30:00Z","endAt":"2026-10-05T00:30:00Z","metadata":{},"source":{"deviceId":"Synthetic pump","eventIds":["fixture-bolus"]}},{"externalId":"fixture-carbs","type":"nutrition.carbohydrates","value":24,"unit":"g","startAt":"2026-10-05T00:30:00Z","endAt":"2026-10-05T00:30:00Z","metadata":{},"source":{"deviceId":"Synthetic pump","eventIds":["fixture-carbs"]}}]"#
      body = "{\"samples\":\(samples),\"effectiveMinDate\":\"2026-10-05T00:00:00Z\",\"effectiveMaxDate\":\"2026-10-06T00:00:00Z\",\"dataSourceMode\":\"tandemSource\"}"
    } else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
#endif
