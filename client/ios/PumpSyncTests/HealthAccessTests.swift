import XCTest
@testable import PumpSync

final class HealthAccessTests: XCTestCase {
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
      "To change access, open iPhone Settings, tap Privacy & Security, tap Health, choose PumpSync, then update the Insulin Delivery and Carbohydrates permissions."
    )
  }
}
