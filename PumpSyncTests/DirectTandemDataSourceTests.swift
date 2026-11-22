import Foundation
import os
import XCTest
@testable import PumpSync

@MainActor
final class DirectTandemDataSourceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_505_600) // 2026-11-01T04:00:00Z
    private let end = Date(timeIntervalSince1970: 1_793_523_600)   // 2026-11-01T09:00:00Z

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json")
                                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "DirectImportFixtures"))
        return try Data(contentsOf: url)
    }

    private func dataSource(now: Date) -> DirectTandemDataSource {
        DirectTandemDataSource(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [URLProtocolStub.self]
            return config
        }, now: { now })
    }

    private func request(region: String = "us") -> TandemSyncRequest {
        .init(tandem: .init(username: "synthetic-fixture", password: "synthetic-fixture", region: region),
              minDate: start, maxDate: end, timeZoneIdentifier: "America/New_York")
    }

    // Exported from the real C# TandemEventClient and TandemSampleNormalizer at
    // backend 35ec09bb2690356a6849bd3819abdeed92b40d49 using only synthetic input.
    func testFallBackGoldenMatchesEveryNormalizedField() throws {
        let expected = try JSONCodec.decoder.decode([SampleDTO].self, from: fixture("tandem-expected-samples"))
        XCTAssertEqual(expected.count, 6)
        let actual = try TandemPumpReports.samples(fixture("tandem-pump-events"), pump: "fixture-pump",
                                                   zone: XCTUnwrap(TimeZone(identifier: "America/New_York")), window: start...end)
        XCTAssertEqual(actual, expected)
        let narrower = try TandemPumpReports.samples(fixture("tandem-pump-events"), pump: "fixture-pump",
                                                     zone: XCTUnwrap(TimeZone(identifier: "America/New_York")),
                                                     window: start.addingTimeInterval(3600)...end)
        XCTAssertEqual(narrower.first, actual.first, "Overlapping windows must return the full closed basal interval")
    }

    func testMalformedOrIrrelevantRowsDoNotDropOtherSamples() throws {
        var input = String(decoding: try fixture("tandem-pump-events"), as: UTF8.self)
        let malformed: [[String: Any]] = [
            ["eventCode": 3, "sequenceNumber": 1, "sequenceGroup": 2, "eventProperties": [:], "pumpDateTime": "2026-11-01T00:00:0099999999999"],
            ["eventCode": 279, "sequenceNumber": 1, "sequenceGroup": 2, "pumpDateTime": "2026-11-01T00:00:00"],
            ["sequenceNumber": 1],
            ["eventCode": 3, "sequenceNumber": "unknown", "eventProperties": [:]],
            ["eventCode": 279, "sequenceNumber": 20, "eventProperties": ["commandedRate": "unexpected"], "pumpDateTime": "2026-11-01T01:30:00"],
            ["eventCode": 999, "sequenceNumber": 30, "eventProperties": [:], "pumpDateTime": "2026-11-01T01:30:00"]
        ]
        // Append the extra rows directly to preserve the fixture's original
        // decimal tokens (NSNumber serialization can change their precision).
        let extra = String(decoding: try JSONSerialization.data(withJSONObject: malformed), as: UTF8.self)
        let opening = try XCTUnwrap(input.firstIndex(of: "["))
        input.insert(contentsOf: extra.dropFirst().dropLast() + ",", at: input.index(after: opening))
        let data = Data(input.utf8)
        let actual = try TandemPumpReports.samples(data, pump: "fixture-pump", zone: XCTUnwrap(TimeZone(identifier: "America/New_York")), window: start...end)
        XCTAssertEqual(actual, try JSONCodec.decoder.decode([SampleDTO].self, from: fixture("tandem-expected-samples")))
        XCTAssertThrowsError(try TandemPumpReports.samples(Data(#"{"events":{}}"#.utf8), pump: "fixture-pump", zone: .gmt, window: start...end))
    }

    func testSubmillisecondOrderingAndWindowBoundsPrecedeLegacyTimestampTruncation() throws {
        let data = Data(#"""
        {"events":[
          {"eventCode":20,"sequenceNumber":2,"pumpDateTime":"2026-11-01T04:00:00.0001000","eventProperties":{"bolusId":9,"insulinDelivered":1}},
          {"eventCode":20,"sequenceNumber":1,"pumpDateTime":"2026-11-01T04:00:00.0005000","eventProperties":{"bolusId":8,"insulinDelivered":1}}
        ]}
        """#.utf8)
        let all = try TandemPumpReports.samples(data, pump: "fixture-pump", zone: .gmt, window: start...end)
        XCTAssertEqual(all.map(\.externalId), ["tandem-bolus-9-20-0-2", "tandem-bolus-8-20-0-1"])
        XCTAssertEqual(all.first?.startAt, all.last?.startAt)
        let filtered = try TandemPumpReports.samples(data, pump: "fixture-pump", zone: .gmt, window: start.addingTimeInterval(0.0003)...end)
        XCTAssertEqual(filtered, Array(all.suffix(1)))
    }

    func testNonexistentLocalTimeUsesStandardOffsetAndWithholdsTrailingBasal() throws {
        let json = Data(#"""
        {"events":[
          {"eventCode":3,"sequenceNumber":2,"pumpDateTime":"2026-03-08T02:30:00","eventProperties":{"commandedBasalRate":1.5}},
          {"eventCode":3,"sequenceNumber":3,"pumpDateTime":"2026-03-08T04:30:00","eventProperties":{"commandedBasalRate":3}}
        ]}
        """#.utf8)
        let samples = try TandemPumpReports.samples(json, pump: "fixture", zone: XCTUnwrap(TimeZone(identifier: "America/New_York")),
                                                    window: Date.distantPast...Date.distantFuture)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.startAt, JSONCodec.parseDate("2026-03-08T07:30:00Z"))
        XCTAssertEqual(samples.first?.value, 1.5)
    }

    func testBothRegionsDownloadOnlyFromTheirOwnTandemEndpoints() async throws {
        let logs = try fixture("tandem-pump-events")
        let expected = try JSONCodec.decoder.decode([SampleDTO].self, from: fixture("tandem-expected-samples"))
        for region in ["us", "eu"] {
            let suffix = region == "us" ? "tandemdiabetes.com" : "eu.tandemdiabetes.com"
            let callback = region == "us" ? "https://sso.tandemdiabetes.com/auth/callback" : "https://source.eu.tandemdiabetes.com/authorize/callback"
            let identity = Data(#"{"pumperId":"fixture-identity"}"#.utf8).base64EncodedString()
            let loginCount = OSAllocatedUnfairLock(initialState: 0)
            let metadataCount = OSAllocatedUnfairLock(initialState: 0)
            URLProtocolStub.requestHandler = { request in
                let url = try XCTUnwrap(request.url)
                let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
                let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
                let status: Int
                let body: Data
                var headers: [String: String] = [:]
                switch url.path {
                case "/accounts/api/login":
                    loginCount.withLock { $0 += 1 }
                    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                    XCTAssertEqual(url.host, "tdcservices." + suffix)
                    XCTAssertEqual(request.httpMethod, "POST")
                    headers["Set-Cookie"] = "fixture_session=isolated; Path=/; Secure; HttpOnly"
                    status = 200
                    body = Data()
                case "/accounts/api/connect/authorize":
                    XCTAssertEqual(url.host, "tdcservices." + suffix)
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "fixture_session=isolated")
                    XCTAssertEqual(query["code_challenge_method"], "S256")
                    XCTAssertEqual(query["code_challenge"]?.count, 43)
                    XCTAssertEqual(query["redirect_uri"], callback)
                    status = 302
                    headers["Location"] = callback + "?code=synthetic"
                    body = Data()
                case "/accounts/api/connect/token":
                    XCTAssertEqual(url.host, "tdcservices." + suffix)
                    XCTAssertEqual(request.httpMethod, "POST")
                    status = 200
                    body = try JSONSerialization.data(withJSONObject: ["access_token": "fixture", "id_token": "fixture." + identity + ".fixture"])
                case "/api/reports/bff/pumper/fixture-identity":
                    XCTAssertEqual(url.host, "source." + suffix)
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
                    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                    let count = metadataCount.withLock { count in count += 1; return count }
                    // Only a report 401 triggers one fresh login.
                    status = region == "eu" && count == 1 ? 401 : 200
                    body = Data(#"{"pumps":[{"assignmentId":199,"lastUploadDate":"2026-05-01T14:00:00"},{"assignmentId":"fixture-pump","maxDateOfEvents":"2026-11-01T04:00:00"}]}"#.utf8)
                case "/api/reports/bff/pump-logs/fixture-pump":
                    XCTAssertEqual(url.host, "source." + suffix)
                    XCTAssertEqual(query["pumperId"], "fixture-identity")
                    XCTAssertEqual(query["eventCodes"], "3,20,21,64,65,66,279")
                    XCTAssertEqual(query["startDate"], "2026-11-01T00:00:00Z")
                    XCTAssertEqual(query["endDate"], "2026-11-01T23:59:59Z")
                    status = 200
                    body = logs
                default:
                    XCTFail("Unexpected endpoint in direct import")
                    throw URLError(.unsupportedURL)
                }
                return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)), body)
            }
            defer { URLProtocolStub.requestHandler = nil }
            let response = try await dataSource(now: end).load(request(region: region))
            XCTAssertEqual(response.samples, expected)
            XCTAssertEqual(response.dataSourceMode, .tandemSource)
            XCTAssertEqual(response.effectiveMinDate, start)
            XCTAssertEqual(response.effectiveMaxDate, end)
            XCTAssertEqual(loginCount.withLock { $0 }, region == "us" ? 1 : 2)
        }
    }

    func testReportQueryUsesPumpCalendarDayAndFiltersByInstant() async throws {
        let cases = [
            ("Europe/Berlin", "2026-11-21T23", "2026-11-22", "00"),
            ("America/New_York", "2026-11-22T03", "2026-11-21", "22")
        ]
        for (zone, utcHour, pumpDay, pumpHour) in cases {
            let start = try XCTUnwrap(JSONCodec.parseDate(utcHour + ":15:00Z"))
            let end = try XCTUnwrap(JSONCodec.parseDate(utcHour + ":45:00Z"))
            let identity = Data(#"{"pumperId":"fixture-identity"}"#.utf8).base64EncodedString()
            URLProtocolStub.requestHandler = { request in
                let url = try XCTUnwrap(request.url)
                var status = 200
                var headers: [String: String] = [:]
                let body: Data
                switch url.path {
                case "/accounts/api/login":
                    body = Data()
                case "/accounts/api/connect/authorize":
                    status = 302
                    headers["Location"] = "https://sso.tandemdiabetes.com/auth/callback?code=synthetic"
                    body = Data()
                case "/accounts/api/connect/token":
                    body = Data(#"{"access_token":"fixture","id_token":"fixture.\#(identity).fixture"}"#.utf8)
                case "/api/reports/bff/pumper/fixture-identity":
                    body = Data(#"{"pumps":[{"assignmentId":"fixture-pump"}]}"#.utf8)
                case "/api/reports/bff/pump-logs/fixture-pump":
                    let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)).queryItems
                    XCTAssertEqual(query?.first(where: { $0.name == "startDate" })?.value, pumpDay + "T00:00:00Z", zone)
                    XCTAssertEqual(query?.first(where: { $0.name == "endDate" })?.value, pumpDay + "T23:59:59Z", zone)
                    body = Data(#"""
                    {"events":[
                      {"eventCode":20,"sequenceNumber":1,"pumpDateTime":"\#(pumpDay)T\#(pumpHour):10:00","eventProperties":{"bolusId":1,"insulinDelivered":1}},
                      {"eventCode":20,"sequenceNumber":2,"pumpDateTime":"\#(pumpDay)T\#(pumpHour):30:00","eventProperties":{"bolusId":2,"insulinDelivered":1}},
                      {"eventCode":20,"sequenceNumber":3,"pumpDateTime":"\#(pumpDay)T\#(pumpHour):50:00","eventProperties":{"bolusId":3,"insulinDelivered":1}}
                    ]}
                    """#.utf8)
                default:
                    XCTFail("Unexpected endpoint in direct import")
                    throw URLError(.unsupportedURL)
                }
                return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)), body)
            }
            defer { URLProtocolStub.requestHandler = nil }
            let response = try await dataSource(now: end).load(
                .init(tandem: request().tandem, minDate: start, maxDate: end, timeZoneIdentifier: zone)
            )
            XCTAssertEqual(response.samples.map(\.externalId), ["tandem-bolus-2-20-0-2"], zone)
            XCTAssertEqual(response.samples.first?.startAt, JSONCodec.parseDate(utcHour + ":30:00Z"), zone)
            XCTAssertEqual(response.effectiveMinDate, start)
            XCTAssertEqual(response.effectiveMaxDate, end)
        }
    }

    func testRejectsForeignAuthorizationRedirectWithoutFollowingIt() async {
        URLProtocolStub.requestHandler = { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.host, "tdcservices.tandemdiabetes.com")
            let status = url.path.hasSuffix("/login") ? 200 : 302
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                         headerFields: ["Location": "https://unexpected.invalid/auth/callback?code=fixture"]))
            return (response, Data())
        }
        defer { URLProtocolStub.requestHandler = nil }
        do {
            _ = try await dataSource(now: end).load(request())
            XCTFail("Accepted a foreign callback")
        } catch {
            XCTAssertEqual(error as? DirectTandemError, .invalidResponse)
        }
    }

    func testRateLimitPreservesHTTPDateOnLoginFailure() async throws {
        URLProtocolStub.requestHandler = { request in
            (try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "Wed, 21 Oct 2037 07:28:00 GMT"])), Data())
        }
        defer { URLProtocolStub.requestHandler = nil }
        do {
            _ = try await dataSource(now: end).load(request())
            XCTFail("Expected a rate limit")
        } catch let error as DirectTandemError {
            XCTAssertEqual(error, .rateLimited(retryAfter: ISO8601DateFormatter().date(from: "2037-10-21T07:28:00Z")))
        }
    }

    func testLoginFailureCategoriesContainOnlySafeInformation() async {
        for (status, expected): (Int, DirectTandemError) in [(401, .credentialsRejected), (429, .rateLimited(retryAfter: nil)), (503, .unavailable)] {
            URLProtocolStub.requestHandler = { request in
                let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil))
                return (response, Data("synthetic-sensitive-body".utf8))
            }
            defer { URLProtocolStub.requestHandler = nil }
            do {
                try await dataSource(now: end).validate(request().tandem)
                XCTFail("Validation must require a successful data read")
            } catch {
                XCTAssertEqual(error as? DirectTandemError, expected)
                XCTAssertFalse(error.localizedDescription.contains("synthetic"))
            }
        }
    }

}
