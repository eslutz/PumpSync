import XCTest
@testable import PumpSync

@MainActor
final class AuthSessionCommitterTests: XCTestCase {
  private let binding = AuthConnectionBinding(backendIdentity: "https://example.com/api", mode: .hosted,
    installationId: "installation", purpose: .liveImport)

  func testEveryConfirmedResponseCommitBoundaryRecoversWithoutResubmittingOrRestoringSource() throws {
    // Removing response journaling or clearing it before the last durable write
    // loses the replacement at one of these crash boundaries.
    for boundary in ["backend.session.current", "proof", "backend.auth.invalidation.v1", "journalDelete"] {
      let persistence = AuthJournalTestPersistence()
      let store = BackendSessionStore(keychain: persistence)
      let source = connection(token: "source")
      try store.save(source)
      let proof = JournalProofProvider()
      let committer = AuthSessionCommitter(store: store)
      let id = try committer.begin(kind: .enrollment, binding: binding, source: source, proofRequestID: "request", proofKeyID: "key")
      try committer.submitted(id, binding: binding, source: source)
      if boundary == "proof" { proof.failRegistration = true }
      else if boundary == "journalDelete" { persistence.failDeleteAccount = "backend.auth.operation-journal.v1" }
      else { persistence.failWriteAccount = boundary }
      XCTAssertThrowsError(try committer.receive(response(token: "target"), operationID: id, binding: binding, proofProvider: proof), boundary)
      XCTAssertEqual(try store.loadAuthJournal()?.phase, .responseReceived, boundary)
      XCTAssertEqual(try store.loadAuthJournal()?.finalProofState, .registered, boundary)
      persistence.failWriteAccount = nil
      persistence.failDeleteAccount = nil
      proof.failRegistration = false
      let restart = AuthSessionCommitter(store: store)
      let repaired = try XCTUnwrap(restart.load(binding: binding, proofProvider: proof), boundary)
      XCTAssertEqual(repaired.session.accessToken, "target", boundary)
      XCTAssertNotEqual(repaired.identity.id, source.identity.id, boundary)
      XCTAssertNil(try store.loadAuthJournal(), boundary)
      XCTAssertEqual(try restart.load(binding: binding, proofProvider: proof), repaired, boundary)
    }
  }

  func testStorageCanonicalizationPreservesCredentialOwnershipWithFractionalExpiry() throws {
    let store = BackendSessionStore(keychain: AuthJournalTestPersistence())
    let fractional = BackendSessionResponse(accessToken: "source", expiresAt: Date(timeIntervalSince1970: 2_000.125),
      serviceMode: "hosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "family",
      refreshToken: "refresh", refreshTokenExpiresAt: Date(timeIntervalSince1970: 3_000.125),
      refreshTokenAbsoluteExpiresAt: Date(timeIntervalSince1970: 4_000.125))
    let source = AuthenticatedConnection(session: fractional, identity: AuthConnectionIdentity(id: UUID(), binding: binding))
    try store.save(source)
    let committer = AuthSessionCommitter(store: store)
    let id = try committer.begin(kind: .refresh, binding: binding, source: source, proofRequestID: "request", proofKeyID: nil)
    XCTAssertNoThrow(try committer.submitted(id, binding: binding, source: source),
      "Keychain date encoding cannot make the same access/refresh credentials look replaced")
  }

  func testResponseJournalWriteFailureLeavesUncertaintyAndForbidsOldRefreshOnRestart() throws {
    let persistence = AuthJournalTestPersistence()
    let store = BackendSessionStore(keychain: persistence)
    let source = connection(token: "source")
    try store.save(source)
    let committer = AuthSessionCommitter(store: store)
    let id = try committer.begin(kind: .refresh, binding: binding, source: source, proofRequestID: "request", proofKeyID: nil)
    try committer.submitted(id, binding: binding, source: source)
    persistence.failWriteAccount = "backend.auth.operation-journal.v1"
    XCTAssertThrowsError(try committer.receive(response(token: "target"), operationID: id, binding: binding, proofProvider: JournalProofProvider()))
    persistence.failWriteAccount = nil
    let restarted = AuthSessionCommitter(store: store)
    XCTAssertThrowsError(try restarted.load(binding: binding, proofProvider: JournalProofProvider())) { error in
      guard case AuthCommitError.uncertainSubmission = error else { return XCTFail("Expected explicit uncertainty") }
    }
    XCTAssertThrowsError(try restarted.begin(kind: .refresh, binding: binding, source: source, proofRequestID: "new", proofKeyID: nil))
    let enrollmentID = try restarted.begin(kind: .enrollment, binding: binding, source: source, proofRequestID: "fresh", proofKeyID: nil)
    try restarted.submitted(enrollmentID, binding: binding, source: source)
    let enrolled = try restarted.receive(response(token: "enrolled"), operationID: enrollmentID, binding: binding, proofProvider: JournalProofProvider())
    XCTAssertNotEqual(enrolled.identity.id, source.identity.id)
    XCTAssertEqual(enrolled.session.accessToken, "enrolled")
  }

  func testSubmittedMarkerFailureKeepsPreparedAndAllowsSafeRestart() throws {
    let persistence = AuthJournalTestPersistence()
    let store = BackendSessionStore(keychain: persistence)
    let source = connection(token: "source")
    try store.save(source)
    let committer = AuthSessionCommitter(store: store)
    let id = try committer.begin(kind: .refresh, binding: binding, source: source, proofRequestID: "request", proofKeyID: nil)
    persistence.failWriteAccount = "backend.auth.operation-journal.v1"
    XCTAssertThrowsError(try committer.submitted(id, binding: binding, source: source))
    persistence.failWriteAccount = nil
    XCTAssertEqual(try store.loadAuthJournal()?.phase, .prepared)
    let restart = AuthSessionCommitter(store: store)
    XCTAssertEqual(try restart.load(binding: binding, proofProvider: JournalProofProvider()), source)
    XCTAssertNil(try store.loadAuthJournal())
  }

  func testReplayRejectsNewerCredentialsEvenWhenConnectionUUIDIsUnchanged() throws {
    let persistence = AuthJournalTestPersistence()
    let store = BackendSessionStore(keychain: persistence)
    let source = connection(token: "source")
    try store.save(source)
    let committer = AuthSessionCommitter(store: store)
    let id = try committer.begin(kind: .refresh, binding: binding, source: source, proofRequestID: "request", proofKeyID: nil)
    try committer.submitted(id, binding: binding, source: source)
    persistence.failWriteAccount = "backend.session.current"
    XCTAssertThrowsError(try committer.receive(response(token: "target"), operationID: id, binding: binding, proofProvider: JournalProofProvider()))
    persistence.failWriteAccount = nil
    let newer = AuthenticatedConnection(session: response(token: "newer"), identity: source.identity)
    try store.save(newer)
    XCTAssertThrowsError(try AuthSessionCommitter(store: store).load(binding: binding, proofProvider: JournalProofProvider()))
    XCTAssertEqual(try store.loadConnection(binding: binding), newer)
    XCTAssertEqual(try store.loadAuthJournal()?.target?.session.accessToken, "target")
  }

  func testDurableGenerationAndFallbackRejectLateResponseAndRestartResurrection() throws {
    for useFallback in [false, true] {
      let persistence = AuthJournalTestPersistence()
      let store = BackendSessionStore(keychain: persistence)
      let source = connection(token: "source")
      try store.save(source)
      let committer = AuthSessionCommitter(store: store)
      let id = try committer.begin(kind: .refresh, binding: binding, source: source, proofRequestID: "request", proofKeyID: nil)
      try committer.submitted(id, binding: binding, source: source)
      persistence.failDeleteAccount = "backend.session.current"
      if useFallback { persistence.failWriteAccount = "backend.auth.invalidation.v1" }
      try committer.invalidate()
      persistence.failWriteAccount = nil
      XCTAssertThrowsError(try committer.receive(response(token: "late"), operationID: id, binding: binding, proofProvider: JournalProofProvider()))
      XCTAssertNil(try AuthSessionCommitter(store: store).load(binding: binding, proofProvider: JournalProofProvider()))
    }
  }

  func testBindingAndSourceMustMatchBeforeSubmission() throws {
    let store = BackendSessionStore(keychain: AuthJournalTestPersistence())
    let source = connection(token: "source")
    try store.save(source)
    let committer = AuthSessionCommitter(store: store)
    let id = try committer.begin(kind: .refresh, binding: binding, source: source, proofRequestID: "request", proofKeyID: nil)
    let changed = AuthenticatedConnection(session: response(token: "changed"), identity: source.identity)
    XCTAssertThrowsError(try committer.submitted(id, binding: binding, source: changed))
    let different = AuthConnectionBinding(backendIdentity: binding.backendIdentity + "/other", mode: .hosted,
      installationId: binding.installationId, purpose: .liveImport)
    XCTAssertThrowsError(try committer.submitted(id, binding: different, source: source))
    XCTAssertThrowsError(try committer.submitted(UUID(), binding: binding, source: source))
    XCTAssertEqual(try store.loadAuthJournal()?.phase, .prepared)
  }

  func testUnavailableJournalReadDefersWithoutDeletingSessionOrProof() throws {
    let persistence = AuthJournalTestPersistence()
    let store = BackendSessionStore(keychain: persistence)
    let source = connection(token: "source")
    try store.save(source)
    let retained = persistence.records
    persistence.failReads = true
    XCTAssertThrowsError(try AuthSessionCommitter(store: store).load(binding: binding, proofProvider: JournalProofProvider()))
    XCTAssertEqual(persistence.records, retained)
    persistence.failReads = false
    XCTAssertEqual(try AuthSessionCommitter(store: store).load(binding: binding, proofProvider: JournalProofProvider()), source)
  }

  private func response(token: String) -> BackendSessionResponse {
    BackendSessionResponse(accessToken: token, expiresAt: .distantFuture, serviceMode: "hosted", dataSourceMode: "tandemSource",
      protocolVersion: 3, sessionFamilyId: "family-\(token)", refreshToken: "refresh-\(token)", refreshTokenExpiresAt: .distantFuture,
      refreshTokenAbsoluteExpiresAt: .distantFuture)
  }

  private func connection(token: String) -> AuthenticatedConnection {
    AuthenticatedConnection(session: response(token: token), identity: AuthConnectionIdentity(id: UUID(), binding: binding))
  }
}

@MainActor
private final class JournalProofProvider: DeviceSessionProofProviding {
  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition { .ready }
  func invalidateHostedProofOperation() {}
  var failRegistration = false
  func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool {
    if failRegistration { throw AuthJournalTestPersistence.Failure.inaccessible }
    return keyId == "key" && requestId == "request"
  }
  func hostedEnrollment(challenge: SessionChallengeResponse, installationId: String, signedTransactionInfo: String) async throws -> HostedDeviceEnrollment { throw APIClientError.invalidResponse }
  func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool { false }
  func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
  func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
  func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
  func discardRegisteredHostedKey() throws -> Bool { false }
  func releaseHostedProofOperation(requestId: String) -> Bool { false }
  func selfHostedEnrollment(challenge: SessionChallengeResponse, installationId: String) throws -> SelfHostedDeviceEnrollment { throw APIClientError.invalidResponse }
  func hostedProofKeyID(requestId: String) throws -> String { "app-attest-key" }
  func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool { keyId == "app-attest-key" }
  func refreshRequest(session: BackendSessionResponse, installationId: String, mode: BackendAccessMode) async throws -> SessionRefreshRequest { throw APIClientError.invalidResponse }
}
