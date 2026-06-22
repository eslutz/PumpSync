import XCTest
@testable import PumpSync

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
      "To change access, open Settings, tap Privacy & Security, tap Health, choose PumpSync, then update the Insulin Delivery and Carbohydrates permissions."
    )
  }
}
