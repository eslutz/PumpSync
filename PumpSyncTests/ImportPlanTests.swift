import XCTest
@testable import PumpSync

final class ImportPlanTests: XCTestCase {
    private let context = ImportSessionSnapshot(backendIdentity: "https://service.example/api", configurationRevision: 1, credentialRevision: 2, sessionFamilyId: "family", dataSourceMode: .tandemSource)
    func testCapturedConcentrationConvertsInsulinExactlyOnceAndLeavesCarbohydratesUnchanged() throws {
        for (concentration, expected): (InsulinConcentration, Decimal) in [(.u100, 1.25), (.u200, 2.5), (.u500, 6.25)] {
            let plan = try ImportPlanner.makePlan(response: response([sample(value: 1.25), sample(id: "carbs", type: "nutrition.carbohydrates", unit: "g", value: 12)]), context: context, concentration: concentration)
            XCTAssertEqual(plan.samples.first { $0.original.externalId == "one" }?.convertedValue, expected)
            XCTAssertEqual(plan.samples.first { $0.original.externalId == "carbs" }?.convertedValue, 12)
        }
    }
    func testZeroValuesAndBasalIntervalsRetainSourceMetadataAndExactConvertedValue() throws {
        let basal = SampleDTO(externalId: "basal", type: "insulin.basal", value: 0.25, unit: "IU", startAt: Date(timeIntervalSince1970: 100), endAt: Date(timeIntervalSince1970: 200), metadata: ["Delivery": "scheduled"], source: SourceDTO(deviceId: "pump", eventIds: ["one", "two"]))
        let plan = try ImportPlanner.makePlan(response: response([basal, sample(value: 0)]), context: context, concentration: .u200)
        XCTAssertEqual(plan.samples.first { $0.original.externalId == "basal" }?.convertedValue, 0.5)
        XCTAssertEqual(plan.samples.first { $0.original.externalId == "basal" }?.original, basal)
        XCTAssertEqual(plan.samples.first { $0.original.externalId == "one" }?.convertedValue, 0)
    }

    func testInvalidRecordRejectsEntirePlan() {
        for invalid in [sample(value: -1), sample(value: Decimal.nan), sample(type: "unknown"), sample(unit: "mg"), sample(end: Date(timeIntervalSince1970: 0))] {
            XCTAssertThrowsError(try ImportPlanner.makePlan(response: response([sample(), invalid]), context: context, concentration: .u100))
        }
    }
    func testConflictingDuplicateIdentityRejectsPlanButIdenticalDuplicatesCollapse() throws {
        XCTAssertThrowsError(try ImportPlanner.makePlan(response: response([sample(), sample(value: 2)]), context: context, concentration: .u100))
        let deduplicated = try ImportPlanner.makePlan(response: response([sample(), sample()]), context: context, concentration: .u100)
        XCTAssertEqual(deduplicated.samples.count, 1)
        XCTAssertEqual(deduplicated.downloadedRecordCount, 2)
        XCTAssertEqual(deduplicated.selectingSamples([]).downloadedRecordCount, 2)
    }
    func testSyntheticPlanRemainsDisplayableButCannotAuthorizeHealth() throws {
        let synthetic = ImportSessionSnapshot(backendIdentity: context.backendIdentity, configurationRevision: 1, credentialRevision: 2, sessionFamilyId: "family", dataSourceMode: .syntheticDemo)
        let plan = try ImportPlanner.makePlan(response: response([sample()], source: .syntheticDemo), context: synthetic, concentration: .u100)
        XCTAssertEqual(plan.samples.count, 1)
        XCTAssertThrowsError(try HealthImportPolicy.authorize(plan: plan, current: synthetic))
    }
    func testMissingUnknownAndMismatchedProvenanceCannotAuthorize() throws {
        for source in [DataSourceMode.unknown, .syntheticDemo] {
            XCTAssertThrowsError(try ImportPlanner.makePlan(response: response([sample()], source: source), context: context, concentration: .u100))
        }
        let missing = try JSONCodec.decoder.decode(TandemSyncResponse.self, from: Data("{\"samples\":[],\"effectiveMinDate\":\"2026-10-01T00:00:00Z\",\"effectiveMaxDate\":\"2026-10-01T01:00:00Z\"}".utf8))
        XCTAssertThrowsError(try ImportPlanner.makePlan(response: missing, context: context, concentration: .u100))
    }
    func testEveryContextChangeInvalidatesEligibleBatch() throws {
        let plan = try ImportPlanner.makePlan(response: response([sample()]), context: context, concentration: .u100)
        let batch = try HealthImportPolicy.authorize(plan: plan, current: context)
        for changed in [
            ImportSessionSnapshot(backendIdentity: "https://other.example/api", configurationRevision: 1, credentialRevision: 2, sessionFamilyId: "family", dataSourceMode: .tandemSource),
            ImportSessionSnapshot(backendIdentity: context.backendIdentity, configurationRevision: 3, credentialRevision: 2, sessionFamilyId: "family", dataSourceMode: .tandemSource),
            ImportSessionSnapshot(backendIdentity: context.backendIdentity, configurationRevision: 1, credentialRevision: 3, sessionFamilyId: "family", dataSourceMode: .tandemSource),
            ImportSessionSnapshot(backendIdentity: context.backendIdentity, configurationRevision: 1, credentialRevision: 2, sessionFamilyId: "new-family", dataSourceMode: .tandemSource)
        ] { XCTAssertThrowsError(try HealthImportPolicy.validate(batch: batch, current: changed)) }
        XCTAssertThrowsError(try HealthImportPolicy.validate(batch: batch, current: nil))
    }
    private func response(_ samples: [SampleDTO], source: DataSourceMode = .tandemSource) -> TandemSyncResponse {
        TandemSyncResponse(samples: samples, effectiveMinDate: Date(timeIntervalSince1970: 0), effectiveMaxDate: Date(timeIntervalSince1970: 200), dataSourceMode: source)
    }
    private func sample(id: String = "one", type: String = "insulin.bolus", unit: String = "IU", value: Decimal = 1, end: Date = Date(timeIntervalSince1970: 100)) -> SampleDTO {
        SampleDTO(externalId: id, type: type, value: value, unit: unit, startAt: Date(timeIntervalSince1970: 100), endAt: end, metadata: [:], source: SourceDTO(deviceId: "pump", eventIds: [id]))
    }
}
