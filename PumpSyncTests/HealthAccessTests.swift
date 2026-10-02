import HealthKit
import XCTest
@testable import PumpSync

@MainActor
final class HealthAccessTests: XCTestCase {
  func testInsulinConcentrationDefaultsToU100() {
    let suiteName = "InsulinConcentrationTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let store = InsulinConcentrationStore(defaults: defaults)

    XCTAssertEqual(store.concentration, .u100)
  }

  func testInsulinConcentrationScalesInsulinForAppleHealth() {
    XCTAssertEqual(InsulinConcentration.u100.appleHealthValue(forPumpReportedValue: 1.25), 1.25)
    XCTAssertEqual(InsulinConcentration.u200.appleHealthValue(forPumpReportedValue: 1.25), 2.5)
    XCTAssertEqual(InsulinConcentration.u500.appleHealthValue(forPumpReportedValue: 1.25), 6.25)
  }

  func testInsulinConcentrationStorePersistsSelection() {
    let suiteName = "InsulinConcentrationTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = InsulinConcentrationStore(defaults: defaults)

    store.concentration = .u500

    XCTAssertEqual(InsulinConcentrationStore(defaults: defaults).concentration, .u500)
  }

  func testWritePermissionRowsDescribeAccessAndHealthAppGuidance() {
    let permissions = HealthWritePermission.defaultWritePermissions(
      statuses: [
        .insulinDelivery: .sharingAuthorized,
        .dietaryCarbohydrates: .sharingDenied
      ]
    )

    XCTAssertEqual(permissions.map(\.title), ["Insulin delivery", "Carbohydrates"])
    XCTAssertEqual(permissions.map(\.statusDescription), ["Allowed", "Not allowed"])
    XCTAssertEqual(
      HealthAccessCopy.healthAppInstructions,
      "Open Settings. Tap Privacy & Security, then Health. Select PumpSync. Turn Insulin Delivery and Carbohydrates on or off."
    )
  }

  func testHealthAccessInstructionsAreReadableSteps() {
    XCTAssertEqual(HealthAccessCopy.healthAppInstructionSteps, [
      "Open Settings.",
      "Tap Privacy & Security, then Health.",
      "Select PumpSync.",
      "Turn Insulin Delivery and Carbohydrates on or off."
    ])
  }

  func testHealthSampleMetadataUsesStableSyncIdentity() {
    let sample = SampleDTO(
      externalId: "event-123",
      type: "nutrition.carbohydrates",
      value: 12,
      unit: "g",
      startAt: Date(timeIntervalSince1970: 1_000),
      endAt: Date(timeIntervalSince1970: 1_000),
      metadata: [:],
      source: SourceDTO(deviceId: "pump-1", eventIds: ["event-123"])
    )

    let metadata = HealthSampleMetadata.values(for: sample)

    XCTAssertEqual(metadata[HKMetadataKeySyncIdentifier] as? String, "pumpsync.nutrition.carbohydrates.event-123")
    XCTAssertEqual(metadata[HKMetadataKeySyncVersion] as? Int, 1)
  }
}

@MainActor
private final class RecordingHealthPersistence: HealthSamplePersisting {
  var saved: [HKQuantitySample] = []
  func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
    type.identifier == HKQuantityTypeIdentifier.insulinDelivery.rawValue ? .sharingAuthorized : .sharingDenied
  }
  func save(_ samples: [HKQuantitySample], completion: @escaping @Sendable (Bool, Error?) -> Void) {
    saved.append(contentsOf: samples)
    completion(true, nil)
  }
}

extension HealthAccessTests {
  func testAdapterOmitsDeniedTypeAndOnlyReturnsConfirmedAuthorizedSamples() async throws {
    let context = ImportSessionSnapshot(backendIdentity: "https://example.com/api", configurationRevision: 1, credentialRevision: 1, sessionFamilyId: "family", dataSourceMode: .tandemSource)
    let insulin = SampleDTO(externalId: "insulin", type: "insulin.bolus", value: 1, unit: "IU", startAt: Date(timeIntervalSince1970: 100), endAt: Date(timeIntervalSince1970: 100), metadata: [:], source: SourceDTO(deviceId: "pump", eventIds: ["insulin"]))
    let carbs = SampleDTO(externalId: "carbs", type: "nutrition.carbohydrates", value: 12, unit: "g", startAt: Date(timeIntervalSince1970: 100), endAt: Date(timeIntervalSince1970: 100), metadata: [:], source: SourceDTO(deviceId: "pump", eventIds: ["carbs"]))
    let plan = try ImportPlanner.makePlan(response: TandemSyncResponse(samples: [insulin, carbs], effectiveMinDate: .distantPast, effectiveMaxDate: .distantFuture, dataSourceMode: .tandemSource), context: context, concentration: .u100)
    let persistence = RecordingHealthPersistence()
    let service = HealthKitService(currentContext: { context }, persistence: persistence)
    service.refreshAuthorizationStatus()
    let written = try await service.save(batch: HealthImportPolicy.authorize(plan: plan, current: context))
    XCTAssertEqual(written, [insulin])
    XCTAssertEqual(persistence.saved.count, 1)
  }

  func testAdapterRechecksContextAtFinalSubmissionAndDoesNotPersistStaleBatch() async throws {
    let context = ImportSessionSnapshot(backendIdentity: "https://example.com/api", configurationRevision: 1, credentialRevision: 1, sessionFamilyId: "family", dataSourceMode: .tandemSource)
    let sample = SampleDTO(externalId: "one", type: "insulin.bolus", value: 1.25, unit: "IU", startAt: Date(timeIntervalSince1970: 100), endAt: Date(timeIntervalSince1970: 100), metadata: [:], source: SourceDTO(deviceId: "pump", eventIds: ["one"]))
    let plan = try ImportPlanner.makePlan(response: TandemSyncResponse(samples: [sample], effectiveMinDate: .distantPast, effectiveMaxDate: .distantFuture, dataSourceMode: .tandemSource), context: context, concentration: .u500)
    let batch = try HealthImportPolicy.authorize(plan: plan, current: context)
    let persistence = RecordingHealthPersistence()
    var reads = 0
    let service = HealthKitService(currentContext: {
      reads += 1
      return reads == 1 ? context : nil
    }, persistence: persistence)
    service.applyScreenshotAuthorization()
    do { _ = try await service.save(batch: batch); XCTFail("Stale context must fail") } catch {}
    XCTAssertTrue(persistence.saved.isEmpty)
    XCTAssertEqual(reads, 2)
  }

  func testAdapterPersistsCapturedConvertedValueExactlyOnceAndReturnsConfirmedOriginal() async throws {
    let context = ImportSessionSnapshot(backendIdentity: "https://example.com/api", configurationRevision: 1, credentialRevision: 1, sessionFamilyId: "family", dataSourceMode: .tandemSource)
    let sample = SampleDTO(externalId: "one", type: "insulin.bolus", value: 1.25, unit: "IU", startAt: Date(timeIntervalSince1970: 100), endAt: Date(timeIntervalSince1970: 100), metadata: [:], source: SourceDTO(deviceId: "pump", eventIds: ["one"]))
    let plan = try ImportPlanner.makePlan(response: TandemSyncResponse(samples: [sample], effectiveMinDate: .distantPast, effectiveMaxDate: .distantFuture, dataSourceMode: .tandemSource), context: context, concentration: .u500)
    let persistence = RecordingHealthPersistence()
    let service = HealthKitService(currentContext: { context }, persistence: persistence)
    service.applyScreenshotAuthorization()
    let written = try await service.save(batch: HealthImportPolicy.authorize(plan: plan, current: context))
    XCTAssertEqual(written, [sample])
    XCTAssertEqual(persistence.saved.count, 1)
    XCTAssertEqual(persistence.saved.first?.quantity.doubleValue(for: .internationalUnit()), 6.25)
  }
}
