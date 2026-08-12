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
