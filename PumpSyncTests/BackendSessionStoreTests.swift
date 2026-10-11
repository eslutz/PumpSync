import XCTest
@testable import PumpSync

@MainActor
final class BackendSessionStoreTests: XCTestCase {
  private let currentAccount = "backend.session.current"

  func testDoesNotLoadOrRecoverSessionFromObsoleteAccount() throws {
    let keychain = SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)")
    let obsoleteAccount = ["backend", "session", "v1"].joined(separator: ".")
    let obsoleteSession = BackendSessionResponse(
      accessToken: "obsolete-token",
      expiresAt: Date(timeIntervalSince1970: 2_000),
      serviceMode: "hosted",
      dataSourceMode: "tandemSource"
    )
    let obsoleteData = try JSONCodec.encoder.encode(obsoleteSession)
    try keychain.writeData(obsoleteData, account: obsoleteAccount)
    defer { try? keychain.deleteAll() }

    let store = BackendSessionStore(keychain: keychain, now: { Date(timeIntervalSince1970: 1_000) })

    XCTAssertNil(store.loadValidSession())
    XCTAssertNil(store.loadRecoverableSession())
    XCTAssertEqual(try keychain.readData(account: obsoleteAccount), obsoleteData)
  }

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
    try keychain.writeData(Data("not valid json".utf8), account: currentAccount)
    let store = BackendSessionStore(keychain: keychain, now: { Date(timeIntervalSince1970: 1_000) })

    XCTAssertNil(store.loadValidSession())
    XCTAssertNil(try keychain.readData(account: currentAccount))
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
    try keychain.writeData(Data(storedSession.utf8), account: currentAccount)
    let store = BackendSessionStore(keychain: keychain, now: { Date(timeIntervalSince1970: 1_000) })

    XCTAssertNil(store.loadValidSession())
    XCTAssertNil(try keychain.readData(account: currentAccount))
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

  func testPersistsAndClearsHostedReenrollmentMarker() throws {
    let store = makeStore(now: { Date(timeIntervalSince1970: 1_000) })

    XCTAssertFalse(store.isHostedReenrollmentPending())
    try store.markHostedReenrollmentPending()
    XCTAssertTrue(store.isHostedReenrollmentPending())

    try store.clearHostedReenrollmentPending()
    XCTAssertFalse(store.isHostedReenrollmentPending())
  }

  private func makeStore(now: @escaping () -> Date) -> BackendSessionStore {
    BackendSessionStore(
      keychain: SecureKeychainStore(service: "dev.ericslutz.PumpSyncTests.\(UUID().uuidString)"),
      now: now
    )
  }
}

@MainActor
final class AuthConnectionPersistenceTests: XCTestCase {
  private func binding(backend: String = "https://service.example/api", mode: BackendAccessMode = .hosted, installation: String = "install", purpose: AuthPurpose = .liveImport) -> AuthConnectionBinding {
    AuthConnectionBinding(backendIdentity: backend, mode: mode, installationId: installation, purpose: purpose)
  }

  private var response: BackendSessionResponse {
    BackendSessionResponse(accessToken: "access", expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "family", refreshToken: "refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
  }

  func testLegacyMigrationPersistsOneIdentityAcrossRestartAndPreservesFlatResponse() throws {
    let persistence = ConnectionTestPersistence()
    persistence.data = try JSONCodec.encoder.encode(response)
    let store = BackendSessionStore(keychain: persistence)
    let migrated = try XCTUnwrap(store.loadConnection(binding: binding()))
    XCTAssertEqual(persistence.writeCount, 1)
    let restarted = BackendSessionStore(keychain: persistence)
    XCTAssertEqual(try restarted.loadConnection(binding: binding()), migrated)
    XCTAssertEqual(persistence.writeCount, 1)
    XCTAssertEqual(try JSONCodec.decoder.decode(BackendSessionResponse.self, from: XCTUnwrap(persistence.data)), response)
    let wireJSON = try JSONSerialization.jsonObject(with: JSONCodec.encoder.encode(response)) as! [String: Any]
    XCTAssertNil(wireJSON["localConnectionIdentity"])
  }

  func testMigrationWriteFailureBlocksUsePreservesLegacyAndRetriesLater() throws {
    let persistence = ConnectionTestPersistence()
    let legacy = try JSONCodec.encoder.encode(response)
    persistence.data = legacy
    persistence.writeFailure = true
    let store = BackendSessionStore(keychain: persistence)
    XCTAssertThrowsError(try store.loadConnection(binding: binding()))
    XCTAssertEqual(persistence.data, legacy)
    XCTAssertEqual(persistence.deleteCount, 0)
    persistence.writeFailure = false
    XCTAssertNotNil(try store.loadConnection(binding: binding()))
    XCTAssertEqual(persistence.writeCount, 2)
  }

  func testUnreadableStorageIsNotAbsentAndDoesNotDeleteOrMigrate() throws {
    let persistence = ConnectionTestPersistence()
    persistence.data = try JSONCodec.encoder.encode(response)
    persistence.readFailure = true
    let store = BackendSessionStore(keychain: persistence)
    XCTAssertThrowsError(try store.loadConnection(binding: binding()))
    XCTAssertEqual(persistence.writeCount, 0)
    XCTAssertEqual(persistence.deleteCount, 0)
    persistence.readFailure = false
    persistence.data = nil
    XCTAssertNil(try store.loadConnection(binding: binding()))
  }

  func testEveryPersistentBindingChangeRejectsStoredConnectionWithoutRebinding() throws {
    let persistence = ConnectionTestPersistence()
    let store = BackendSessionStore(keychain: persistence)
    let connection = AuthenticatedConnection(session: response, identity: AuthConnectionIdentity(id: UUID(), binding: binding()))
    try store.save(connection)
    let data = persistence.data
    for changed in [binding(backend: "https://other.example/api"), binding(mode: .selfHosted), binding(installation: "other"), binding(purpose: .preview)] {
      XCTAssertThrowsError(try store.loadConnection(binding: changed))
      XCTAssertEqual(persistence.data, data)
    }
    XCTAssertEqual(try store.loadConnection(binding: binding()), connection)
    XCTAssertEqual(persistence.writeCount, 1)
  }

  func testMalformedIdentityDoesNotDowngradeToLegacyOrDeleteData() throws {
    let persistence = ConnectionTestPersistence()
    var json = try JSONSerialization.jsonObject(with: JSONCodec.encoder.encode(response)) as! [String: Any]
    json["localConnectionIdentity"] = ["id": "invalid"]
    persistence.data = try JSONSerialization.data(withJSONObject: json)
    let before = persistence.data
    XCTAssertThrowsError(try BackendSessionStore(keychain: persistence).loadConnection(binding: binding()))
    XCTAssertEqual(persistence.data, before)
    XCTAssertEqual(persistence.writeCount, 0)
    XCTAssertEqual(persistence.deleteCount, 0)
  }
}

@MainActor
final class ConnectionTestPersistence: BackendSessionPersistence {
  enum Failure: Error { case inaccessible }
  var records: [String: Data] = [:]
  var data: Data? {
    get { records["backend.session.current"] }
    set { records["backend.session.current"] = newValue }
  }
  var readFailure = false
  var writeFailure = false
  var writeCount = 0
  var deleteCount = 0
  func readData(account: String) throws -> Data? {
    if readFailure { throw Failure.inaccessible }
    return records[account]
  }
  func writeData(_ data: Data, account: String) throws {
    writeCount += 1
    if writeFailure { throw Failure.inaccessible }
    records[account] = data
  }
  func delete(account: String) throws {
    deleteCount += 1
    records[account] = nil
  }
}

@MainActor
final class AuthJournalTestPersistence: BackendSessionPersistence {
  enum Failure: Error { case inaccessible }
  var records: [String: Data] = [:]
  nonisolated(unsafe) var failWriteAccount: String?
  var failDeleteAccount: String?
  var failReads = false
  var failAllWrites = false
  var failWriteOrdinal: Int?
  var writeCounts: [String: Int] = [:]
  func readData(account: String) throws -> Data? {
    if failReads { throw Failure.inaccessible }
    return records[account]
  }
  func writeData(_ data: Data, account: String) throws {
    writeCounts[account, default: 0] += 1
    if failAllWrites || (failWriteAccount == account && (failWriteOrdinal == nil || writeCounts[account] == failWriteOrdinal)) {
      throw Failure.inaccessible
    }
    records[account] = data
  }
  func delete(account: String) throws {
    if failDeleteAccount == account { throw Failure.inaccessible }
    records[account] = nil
  }
}
