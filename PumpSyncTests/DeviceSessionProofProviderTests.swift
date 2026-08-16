import XCTest
@testable import PumpSync

final class DeviceSessionProofProviderTests: XCTestCase {
  func testCanonicalPayloadMatchesBackendProtocolVector() {
    let payload = DeviceProofPayload(
      operation: "refresh",
      path: "/api/v1/session/refresh",
      installationId: "installation-1",
      requestId: "request-1",
      issuedAt: Date(timeIntervalSince1970: 1_786_795_200),
      credential: "refresh-token"
    )

    XCTAssertEqual(
      payload.encoded.base64EncodedString(),
      "AAAAGVB1bXBTeW5jLkRldmljZVNlc3Npb24udjIAAAAHcmVmcmVzaAAAABcvYXBpL3YxL3Nlc3Npb24vcmVmcmVzaAAAAA5pbnN0YWxsYXRpb24tMQAAAAlyZXF1ZXN0LTEAAAAKMTc4Njc5NTIwMAAAACAOsXZD1OkmEWN4OkIIWcksfSEvqWJBBqErUQr77CZhIA=="
    )
  }
}
