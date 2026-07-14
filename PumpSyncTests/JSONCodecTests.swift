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

  func testDecodesNumericMetadataAndEventIdsAsStrings() throws {
    let data = Data("""
    {
      "cursor": 123456,
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
      ]
    }
    """.utf8)

    let response = try JSONCodec.decoder.decode(TandemSyncResponse.self, from: data)

    XCTAssertEqual(response.cursor, "123456")
    XCTAssertEqual(response.samples[0].externalId, "987654")
    XCTAssertEqual(response.samples[0].unit, "1")
    XCTAssertEqual(response.samples[0].metadata["rateIUPerHour"], "0.5")
    XCTAssertEqual(response.samples[0].source.deviceId, "12345")
    XCTAssertEqual(response.samples[0].source.eventIds, ["456", "789"])
  }

  func testAPIClientErrorClassifiesTransientStatuses() {
    XCTAssertTrue(APIClientError.invalidResponse.isTransient)
    XCTAssertTrue(APIClientError.httpStatus(429, nil).isTransient)
    XCTAssertTrue(APIClientError.httpStatus(503, nil).isTransient)
    XCTAssertFalse(APIClientError.httpStatus(400, nil).isTransient)
    XCTAssertFalse(APIClientError.httpStatus(401, nil).isTransient)
  }

  func testEncodesTandemSyncRequestWithBoundedDateWindow() throws {
    let maxDate = Date(timeIntervalSince1970: 1_000_000)
    let minDate = maxDate.addingTimeInterval(-AppConstants.tandemSyncWindowInterval)
    let request = TandemSyncRequest(
      tandem: TandemCredentials(username: "user@example.com", password: "secret", region: TandemRegion.us.rawValue),
      deviceId: nil,
      minDate: minDate,
      maxDate: maxDate
    )

    let data = try JSONCodec.encoder.encode(request)
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let encodedMinDate = try XCTUnwrap(payload["minDate"] as? String)
    let encodedMaxDate = try XCTUnwrap(payload["maxDate"] as? String)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let decodedMinDate = try XCTUnwrap(formatter.date(from: encodedMinDate))
    let decodedMaxDate = try XCTUnwrap(formatter.date(from: encodedMaxDate))
    XCTAssertLessThanOrEqual(decodedMaxDate.timeIntervalSince(decodedMinDate), AppConstants.tandemSyncWindowInterval)
  }
}
