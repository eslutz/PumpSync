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

  func testSubscriptionEnrollmentDoesNotRetryServerFailure() async {
    let calls = LockIsolated(0)
    URLProtocolStub.requestHandler = { request in
      calls.modify { $0 += 1 }
      let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
      return (response, Data())
    }
    let client = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 2
    )
    let enrollment = HostedDeviceEnrollment(
      requestId: "request-1", issuedAt: Date(), challengeToken: "challenge",
      keyId: "key-1", proofKind: "attestation", proof: "proof"
    )

    do {
      _ = try await client.createSubscriptionSession(SubscriptionSessionRequest(
        signedTransactionInfo: "transaction", installationId: "installation-1", deviceEnrollment: enrollment
      ))
      XCTFail("Expected server failure")
    } catch {}

    XCTAssertEqual(calls.value, 1)
  }

  func testSessionRefreshDoesNotRetryServerFailure() async {
    let calls = LockIsolated(0)
    URLProtocolStub.requestHandler = { request in
      calls.modify { $0 += 1 }
      let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
      return (response, Data())
    }
    let client = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 2
    )

    do {
      _ = try await client.refreshSession(SessionRefreshRequest(
        installationId: "installation-1", refreshToken: "refresh", requestId: "request-1",
        issuedAt: Date(), proof: "proof"
      ))
      XCTFail("Expected server failure")
    } catch {}

    XCTAssertEqual(calls.value, 1)
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

  func modify(_ body: (inout Value) -> Void) {
    lock.lock()
    body(&storedValue)
    lock.unlock()
  }

  var value: Value {
    lock.lock()
    defer { lock.unlock() }
    return storedValue
  }
}
