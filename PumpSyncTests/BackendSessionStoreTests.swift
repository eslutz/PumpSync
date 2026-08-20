import XCTest
@testable import PumpSync

@MainActor
final class BackendSessionStoreTests: XCTestCase {
  func testPersistsAndReloadsValidSession() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    let session = BackendSessionResponse(
      accessToken: "token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
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
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
      )
    )

    XCTAssertNil(store.loadValidSession())
  }

  func testPreservesExpiredAccessTokenWhenRefreshCredentialIsStillRenewable() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 2_000) })
    let session = BackendSessionResponse(
      accessToken: "expired-access-token",
      expiresAt: Date(timeIntervalSince1970: 1_999),
      serviceMode: "selfHosted",
      dataSourceMode: "tandemSource",
      protocolVersion: 3,
      sessionFamilyId: "family-1",
      refreshToken: "refresh-token",
      refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_000),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000)
    )
    try store.save(session)

    XCTAssertNil(store.loadValidSession())
    XCTAssertEqual(store.loadRecoverableSession(), session)
  }

  func testRejectsSessionInsideRefreshWindow() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    try store.save(
      BackendSessionResponse(
        accessToken: "token",
        expiresAt: Date(timeIntervalSince1970: 1_299),
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
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
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
      )
    )

    XCTAssertNil(store.loadValidSession())
  }

  func testRejectsPreProtocol3SessionEvenWhileAccessTokenIsFresh() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    try store.save(
      BackendSessionResponse(
        accessToken: "old-token",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        serviceMode: "hosted",
        dataSourceMode: "tandemSource",
        protocolVersion: 2,
        sessionFamilyId: "old-family",
        refreshToken: "",
        refreshTokenExpiresAt: .distantPast,
        refreshTokenAbsoluteExpiresAt: .distantPast
      )
    )

    XCTAssertNil(store.loadValidSession())
    XCTAssertNil(store.loadRecoverableSession())
  }

  func testDiscardsCorruptedStoredData() throws {
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)")
    try keychain.writeData(Data("not valid json".utf8), account: "backend.session.v1")
    let store = BackendSessionStore(keychain: keychain, now: { Date(timeIntervalSince1970: 1_000) })

    XCTAssertNil(store.loadValidSession())
    XCTAssertNil(try keychain.readData(account: "backend.session.v1"))
  }

  func testDiscardsSessionWithoutRenewableCredentialFields() throws {
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)")
    let storedSession = """
      {
        "accessToken": "token",
        "expiresAt": "1970-01-01T00:33:20Z",
        "serviceMode": "hosted",
        "dataSourceMode": "tandemSource"
      }
      """
    try keychain.writeData(Data(storedSession.utf8), account: "backend.session.v1")
    let store = BackendSessionStore(keychain: keychain, now: { Date(timeIntervalSince1970: 1_000) })

    XCTAssertNil(store.loadValidSession())
    XCTAssertNil(try keychain.readData(account: "backend.session.v1"))
  }

  func testDeleteRemovesStoredSession() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })
    try store.save(
      BackendSessionResponse(
        accessToken: "token",
        expiresAt: Date(timeIntervalSince1970: 2_000),
        serviceMode: "hosted",
        dataSourceMode: "tandemSource"
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
