import XCTest
@testable import PumpSync

final class JSONCodecTests: XCTestCase {
  func testDecodesFractionalSecondDates() throws {
    let data = Data("""
    {
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
      ],
      "effectiveMinDate": "2026-06-16T12:00:00Z",
      "effectiveMaxDate": "2026-06-17T12:01:00.123Z"
    }
    """.utf8)

    let response = try JSONCodec.decoder.decode(TandemSyncResponse.self, from: data)

    XCTAssertEqual(response.samples.count, 1)
    XCTAssertEqual(response.samples[0].type, "insulin.bolus")
  }

  func testDecodesNumericMetadataAndEventIdsAsStrings() throws {
    let data = Data("""
    {
      "samples": [
        {
          "externalId": 987654,
          "type": "insulin.basal",
          "value": 0.25,
          "unit": 1,
          "startAt": "2026-06-17T12:00:00Z",
          "endAt": "2026-06-17T12:05:00Z",
          "metadata": {
            "rateIUPerHour": 0.5,
            "sourceKind": "basal"
          },
          "source": {
            "deviceId": 12345,
            "eventIds": [456, "789"]
          }
        }
      ],
      "effectiveMinDate": "2026-06-17T12:00:00Z",
      "effectiveMaxDate": "2026-06-17T12:05:00Z"
    }
    """.utf8)

    let response = try JSONCodec.decoder.decode(TandemSyncResponse.self, from: data)

    XCTAssertEqual(response.samples[0].externalId, "987654")
    XCTAssertEqual(response.samples[0].unit, "1")
    XCTAssertEqual(response.samples[0].metadata["rateIUPerHour"], "0.5")
    XCTAssertEqual(response.samples[0].source.deviceId, "12345")
    XCTAssertEqual(response.samples[0].source.eventIds, ["456", "789"])
  }

  func testAPIClientErrorClassifiesTransientStatuses() {
    XCTAssertTrue(APIClientError.invalidResponse.isTransient)
    // 429 must not be blind-retried: the backend's rate-limit windows are
    // minutes to an hour, so an immediate retry is guaranteed to fail.
    XCTAssertFalse(APIClientError.httpStatus(429, code: nil, message: nil).isTransient)
    XCTAssertTrue(APIClientError.httpStatus(503, code: nil, message: nil).isTransient)
    XCTAssertFalse(APIClientError.httpStatus(400, code: nil, message: nil).isTransient)
    XCTAssertFalse(APIClientError.httpStatus(401, code: nil, message: nil).isTransient)
  }

  func testAPIClientErrorClassifiesTandemCredentialAndRateLimitFailures() {
    XCTAssertTrue(APIClientError.httpStatus(424, code: "tandem_authentication_failed", message: nil).isTandemCredentialFailure)
    XCTAssertFalse(APIClientError.httpStatus(401, code: nil, message: nil).isTandemCredentialFailure)
    XCTAssertTrue(APIClientError.httpStatus(429, code: "rate_limit_exceeded", message: nil).isRateLimited)
    XCTAssertFalse(APIClientError.httpStatus(500, code: nil, message: nil).isRateLimited)
  }
}
