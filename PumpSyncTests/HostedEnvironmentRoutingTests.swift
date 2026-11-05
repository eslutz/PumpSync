import XCTest
@testable import PumpSync

@MainActor
final class HostedEnvironmentRoutingTests: XCTestCase {
  func testPersistedProductionRouteNeverUsesSandboxBuildDefault() {
    let defaults = UserDefaults(suiteName: "HostedRouting-\(UUID().uuidString)")!
    defaults.set("production", forKey: "backend.hostedEnvironment")
    let configuration = BackendConfigurationStore(defaults: defaults)
    XCTAssertEqual(configuration.selectedBaseURL?.absoluteString, "https://api.pumpsync.ericslutz.dev/api")
  }
}
