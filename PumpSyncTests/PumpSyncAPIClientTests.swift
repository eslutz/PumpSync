import XCTest
@testable import PumpSync

@MainActor
final class PumpSyncAPIClientTests: XCTestCase {
  override func tearDown() {
    URLProtocolStub.requestHandler = nil
    super.tearDown()
  }

  func testWarmupRequestsCapabilitiesWithoutAuthentication() async {
    let path = LockIsolated<String?>(nil)
    URLProtocolStub.requestHandler = { request in
      path.set(request.url?.path)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"serviceMode":"hosted","dataSourceMode":"tandemSource"}"#.utf8))
    }

    let client = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )

    await client.warmup()

    XCTAssertEqual(path.value, "/api/v1/capabilities")
  }
}

private final class LockIsolated<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Value

  init(_ value: Value) {
    storedValue = value
  }

  func set(_ value: Value) {
    lock.lock()
    storedValue = value
    lock.unlock()
  }

  var value: Value {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }
}
