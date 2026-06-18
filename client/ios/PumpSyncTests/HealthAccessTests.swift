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
      "To change access, open Health, tap Sharing, tap Apps, choose PumpSync, then update Insulin Delivery and Carbohydrates."
    )
  }
}
