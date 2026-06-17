import XCTest
@testable import PumpSync

final class JSONCodecTests: XCTestCase {
  func testDecodesFractionalSecondDates() throws {
    let data = Data("""
    {
      "cursor": null,
      "samples": [
        {
          "externalId": "sample-1",
          "type": "insulin.bolus",
          "value": 1.25,
          "unit": "IU",
          "startAt": "2026-06-17T12:00:00.123Z",
          "endAt": "2026-06-17T12:01:00.123Z",
          "metadata": {},
          "source": {
            "deviceId": "pump-1",
            "eventIds": ["3"]
          }
        }
      ]
    }
    """.utf8)

    let response = try JSONCodec.decoder.decode(TandemSyncResponse.self, from: data)

    XCTAssertEqual(response.samples.count, 1)
    XCTAssertEqual(response.samples[0].type, "insulin.bolus")
  }

  func testAPIClientErrorClassifiesTransientStatuses() {
    XCTAssertTrue(APIClientError.invalidResponse.isTransient)
    XCTAssertTrue(APIClientError.httpStatus(429, nil).isTransient)
    XCTAssertTrue(APIClientError.httpStatus(503, nil).isTransient)
    XCTAssertFalse(APIClientError.httpStatus(400, nil).isTransient)
    XCTAssertFalse(APIClientError.httpStatus(401, nil).isTransient)
  }
}
