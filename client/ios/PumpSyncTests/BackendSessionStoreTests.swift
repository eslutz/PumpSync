import XCTest
@testable import PumpSync

@MainActor
final class BackendSessionStoreTests: XCTestCase {
  func testPersistsAndReloadsValidSession() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      entitlementActive: true,
      serviceMode: "hosted"
    )

    try store.save(session)

    XCTAssertEqual(store.loadValidSession(), session)
  }

  func testRejectsExpiredSession() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 2_000) })
    try store.save(
      BackendSessionResponse(
        accessToken: "token",
        expiresAt: Date(timeIntervalSince1970: 1_999),
        entitlementActive: true,
        serviceMode: "hosted"
      )
    )

    XCTAssertNil(store.loadValidSession())
  }

  func testRejectsSessionInsideRefreshWindow() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    try store.save(
      BackendSessionResponse(
        accessToken: "token",
        expiresAt: Date(timeIntervalSince1970: 1_299),
        entitlementActive: true,
        serviceMode: "hosted"
      )
    )

    XCTAssertNil(store.loadValidSession())
  }

  func testRejectsEmptyAccessToken() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    try store.save(
      BackendSessionResponse(
        accessToken: "",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        entitlementActive: true,
        serviceMode: "hosted"
      )
    )

    XCTAssertNil(store.loadValidSession())
  }

  func testDeleteRemovesStoredSession() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    try store.save(
      BackendSessionResponse(
        accessToken: "token",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        entitlementActive: true,
        serviceMode: "hosted"
      )
    )

    try store.delete()

    XCTAssertNil(store.loadValidSession())
  }

  private func makeStore(now: @escaping () -> Date) -> BackendSessionStore {
    BackendSessionStore(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      now: now
    )
  }
}
