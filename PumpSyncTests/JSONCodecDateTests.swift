import XCTest
@testable import PumpSync

@MainActor
final class JSONCodecDateTests: XCTestCase {
  private struct Payload: Codable, Sendable { let date: Date }

  func testPreservesWireTimestampFormatsAndMillisecondSemantics() throws {
    let fixtures: [(String, TimeInterval)] = [
      ("2026-06-17T12:00:00Z", 1_781_697_600),
      ("2026-06-17T12:00:00.1Z", 1_781_697_600.1),
      ("2026-06-17T12:00:00.123Z", 1_781_697_600.123),
      ("2026-06-17T12:00:00.1234567Z", 1_781_697_600.123),
      ("2026-06-17T12:00:00.9999999Z", 1_781_697_600.999),
      ("2026-06-17T14:30:00.123+02:30", 1_781_697_600.123),
      ("2026-06-17T07:00:00-05:00", 1_781_697_600),
      ("2026-06-17T14:30:00+0230", 1_781_697_600),
      ("1969-12-31T23:59:59.1234567Z", -0.877)
    ]
    for (wireDate, expected) in fixtures {
      let data = try JSONSerialization.data(withJSONObject: ["date": wireDate])
      let decoded = try JSONCodec.decoder.decode(Payload.self, from: data)
      XCTAssertEqual(decoded.date.timeIntervalSince1970, expected, accuracy: 0.000001, wireDate)
    }
  }

  func testRejectsMalformedDatesWithoutEchoingTheirContent() throws {
    for value in ["invalid-private-value", "2026-99-17T12:00:00Z", "2026-06-17T12:00:00"] {
      let data = try JSONSerialization.data(withJSONObject: ["date": value])
      XCTAssertThrowsError(try JSONCodec.decoder.decode(Payload.self, from: data)) { error in
        guard case DecodingError.dataCorrupted(let context) = error else { return XCTFail("Expected invalid date error") }
        XCTAssertEqual(context.codingPath.map(\.stringValue), ["date"])
        XCTAssertFalse(context.debugDescription.contains(value))
      }
    }
  }

  func testEncodingRetainsWholeSecondISO8601Contract() throws {
    let encoded = try JSONCodec.encoder.encode(Payload(date: Date(timeIntervalSince1970: 1_781_697_600.123)))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: String])
    XCTAssertEqual(object["date"], "2026-06-17T12:00:00Z")
  }

  func testDecoderConfigurationDoesNotLeakBetweenOperations() throws {
    let customized = JSONCodec.decoder
    customized.dateDecodingStrategy = .secondsSince1970
    let decoded = try JSONCodec.decoder.decode(Payload.self, from: Data(#"{"date":"2026-06-17T12:00:00Z"}"#.utf8))
    XCTAssertEqual(decoded.date.timeIntervalSince1970, 1_781_697_600)
  }

  func testConcurrentResponseDecodingUsesIndependentCodecs() async throws {
    let data = Data(#"{"date":"2026-06-17T14:30:00.1234567+02:30"}"#.utf8)
    let results = try await withThrowingTaskGroup(of: Date.self) { group in
      for _ in 0..<50 {
        group.addTask { try await APIResponseDecoder.decode(Payload.self, from: data).date }
      }
      var dates: [Date] = []
      for try await date in group { dates.append(date) }
      return dates
    }
    XCTAssertEqual(results.count, 50)
    XCTAssertTrue(results.allSatisfy { abs($0.timeIntervalSince1970 - 1_781_697_600.123) < 0.000001 })
  }

  func testCanceledDecodingDoesNotReturnAResponse() async {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await APIResponseDecoder.decode(Payload.self, from: Data(#"{"date":"2026-06-17T12:00:00Z"}"#.utf8))
    }
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {
    } catch { XCTFail("Unexpected error: \(error)") }
  }
}
