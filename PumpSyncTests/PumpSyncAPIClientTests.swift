import XCTest
@testable import PumpSync

@MainActor
final class PumpSyncAPIClientTests: XCTestCase {
  override func tearDown() {
    URLProtocolStub.requestHandler = nil
    super.tearDown()
  }

  func testWarmupRequestsCapabilitiesWithoutAuthentication() async throws {
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

    try await client.warmup()

    XCTAssertEqual(path.value, "/api/v1/capabilities")
  }

  func testWarmupRetriesOneTransientFailure() async throws {
    let calls = LockIsolated(0)
    URLProtocolStub.requestHandler = { request in
      let call = calls.value
      calls.modify { $0 += 1 }
      if call == 0 {
        throw URLError(.timedOut)
      }
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, Data())
    }
    let client = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )

    try await client.warmup()

    XCTAssertEqual(calls.value, 2)
  }

  func testWarmupStopsAfterOneRetry() async {
    let calls = LockIsolated(0)
    URLProtocolStub.requestHandler = { _ in
      calls.modify { $0 += 1 }
      throw URLError(.cannotConnectToHost)
    }
    let client = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )

    do {
      try await client.warmup()
      XCTFail("Expected warm-up failure")
    } catch {}

    XCTAssertEqual(calls.value, 2)
  }

  func testHostedEnrollmentChallengeAllowsContainerColdStart() async throws {
    let timeout = LockIsolated<TimeInterval?>(nil)
    URLProtocolStub.requestHandler = { request in
      timeout.set(request.timeoutInterval)
      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"protocolVersion":3,"proofKind":"appAttest","challengeToken":"challenge","expiresAt":"2099-01-01T00:00:00Z"}"#.utf8))
    }
    let client = PumpSyncAPIClient(
      baseURL: URL(string: "https://example.com/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 0
    )

    _ = try await client.createSessionChallenge(SessionChallengeRequest(
      installationId: "installation-1",
      purpose: "hostedEnrollment",
      requestHash: "request-hash"
    ))

    XCTAssertEqual(timeout.value, 75)
  }

  func testRequestRetriesKeepTheBaseURLCapturedAtRequestStart() async throws {
    let firstRequestStarted = expectation(description: "first request started")
    let allowFirstRequestToFail = DispatchSemaphore(value: 0)
    let hosts = LockIsolated<[String]>([])
    URLProtocolStub.requestHandler = { request in
      hosts.modify { $0.append(request.url?.host ?? "missing") }
      if hosts.value.count == 1 {
        firstRequestStarted.fulfill()
        allowFirstRequestToFail.wait()
        throw URLError(.cannotConnectToHost)
      }

      let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
      )!
      return (response, Data(#"{"protocolVersion":3,"proofKind":"appAttest","challengeToken":"challenge","expiresAt":"2099-01-01T00:00:00Z"}"#.utf8))
    }
    let client = PumpSyncAPIClient(
      baseURL: URL(string: "https://hosted.example/api")!,
      urlSession: URLProtocolStub.makeSession(),
      maxRetryCount: 1
    )

    let request = Task {
      try await client.createSessionChallenge(SessionChallengeRequest(
        installationId: "installation-1",
        purpose: "hostedEnrollment",
        requestHash: "request-hash"
      ))
    }
    await fulfillment(of: [firstRequestStarted], timeout: 1)
    client.updateBaseURL(URL(string: "https://self-hosted.example/api")!)
    allowFirstRequestToFail.signal()
    _ = try await request.value

    XCTAssertEqual(hosts.value, ["hosted.example", "hosted.example"])
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
      ), mode: .hosted)
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
