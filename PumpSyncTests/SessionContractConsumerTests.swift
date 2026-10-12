import XCTest
import Synchronization
@testable import PumpSync

/// Resources exist only while validate-session-contract.sh runs the backend exporter.
/// Normal unit/Cloud runs skip this separate, pinned cross-repository lane.
@MainActor
final class SessionContractConsumerTests: XCTestCase {
  func testHostedExportCompletesAuthRotationThroughGuardedImport() async throws { try await consume(mode: "hosted") }
  func testSelfHostedExportCompletesAuthRotationThroughGuardedImport() async throws { try await consume(mode: "selfHosted") }

  private func consume(mode: String) async throws {
    guard let url = Bundle(for: Self.self).url(forResource: mode, withExtension: "json") else {
      throw XCTSkip("Run scripts/ios/validate-session-contract.sh for backend-generated resources")
    }
    let artifact = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let beforeData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(artifact["before"]))
    let afterData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(artifact["after"]))
    let before = try JSONCodec.decoder.decode(BackendSessionResponse.self, from: beforeData)
    let after = try JSONCodec.decoder.decode(BackendSessionResponse.self, from: afterData)
    XCTAssertNotEqual(before.sessionFamilyId, after.sessionFamilyId)
    XCTAssertNotEqual(before.accessToken, after.accessToken)
    XCTAssertNotEqual(before.refreshToken, after.refreshToken)
    XCTAssertEqual(before.protocolVersion, 3)
    XCTAssertEqual(before.dataSourceMode, "tandemSource")
    let suite = "SessionContract.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); URLProtocolStub.requestHandler = nil }
    let config = BackendConfigurationStore(defaults: defaults)
    if mode == "selfHosted" { config.mode = .selfHosted; config.selfHostedBaseURLString = "https://contract.example/api" }
    let api = PumpSyncAPIClient(baseURL: try XCTUnwrap(config.selectedBaseURL), urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
    let clock = Mutex(before.expiresAt.addingTimeInterval(-299))
    let paths = Mutex<[String]>([])
    let sample = SampleDTO(externalId: "contract-sample", type: "insulin.bolus", value: 1, unit: "IU", startAt: Date(), endAt: Date(), metadata: [:], source: SourceDTO(deviceId: "test-only-device", eventIds: ["test-only-event"]))
    let syncData = try JSONCodec.encoder.encode(ImportResponse(samples: [sample], effectiveMinDate: Date().addingTimeInterval(-3600), effectiveMaxDate: Date()))
    URLProtocolStub.requestHandler = { request in
      let path = try XCTUnwrap(request.url?.path)
      paths.withLock { $0.append(path) }
      let data: Data
      if path.hasSuffix("/session/refresh") {
        clock.withLock { $0 = Date() }
        data = afterData
      } else if path.hasSuffix("/sync/tandem") {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + after.accessToken)
        data = syncData
      } else if path.hasSuffix("/self-host/session") || path.hasSuffix("/subscription/session") { data = beforeData }
      else { throw APIClientError.invalidResponse }
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
    }
    // Consume the exact pre-rotation export through the actual HTTP decoder too.
    let received: BackendSessionResponse
    if mode == "selfHosted" {
      received = try await api.createSelfHostedSession(.init(installationId: config.installationId, deviceEnrollment: .init(requestId: "test", issuedAt: Date(), challengeToken: "test", publicKey: "test", signature: "test")))
    } else {
      received = try await api.createSubscriptionSession(.init(signedTransactionInfo: "test", installationId: config.installationId, deviceEnrollment: .init(requestId: "test", issuedAt: Date(), challengeToken: "test", keyId: "test-key", proofKind: "attestation", proof: "test")))
    }
    let keychain = SecureKeychainStore(service: suite)
    defer { try? keychain.deleteAll() }
    let sessionStore = BackendSessionStore(keychain: keychain, now: { clock.withLock { $0 } })
    try sessionStore.save(received)
    let auth = AuthService(apiClient: api, configurationStore: config, sessionStore: sessionStore, proofProvider: ContractProof())
    let credentials = TandemCredentialStore(keychain: keychain)
    try credentials.saveValidated(.init(username: "test@example.com", password: "test", region: "us"))
    let initialIdentity = try XCTUnwrap(sessionStore.loadConnection(binding: XCTUnwrap(auth.connectionBinding))?.identity)
    let health = ContractHealth(current: { auth.currentImportSnapshot(credentialRevision: credentials.revision) })
    let metadata = SyncMetadataStore(defaults: defaults)
    let attempts = SyncAttemptStore(defaults: defaults)
    let coordinator = SyncCoordinator(apiClient: api, authService: auth, credentialStore: credentials, healthKitService: health, importedSampleLedger: ImportedSampleLedger(keychain: keychain, defaults: defaults), syncMetadataStore: metadata, attemptStore: attempts)
    coordinator.setForegroundActive(true)
    let outcome = await coordinator.run(reason: .manual)
    XCTAssertEqual(outcome, .completed)
    XCTAssertEqual(auth.authenticatedConnection?.identity, initialIdentity)
    XCTAssertEqual(auth.session?.sessionFamilyId, after.sessionFamilyId)
    XCTAssertEqual(health.writes, 1)
    XCTAssertEqual(metadata.metadata.lastImportedCount, 1)
    XCTAssertNotNil(metadata.metadata.syncWatermark)
    XCTAssertEqual(attempts.history.first?.outcome, .completed)
    XCTAssertEqual(paths.withLock { $0.filter { $0.hasSuffix("/session/refresh") }.count }, 1)
    XCTAssertEqual(paths.withLock { $0.filter { $0.hasSuffix("/sync/tandem") }.count }, 1)
  }

  private struct ImportResponse: Encodable {
    var dataSourceMode = "tandemSource"
    let samples: [SampleDTO]
    let effectiveMinDate: Date
    let effectiveMaxDate: Date
  }
  private final class ContractHealth: SyncHealthWriting {
    let current: () -> ImportSessionSnapshot?
    init(current: @escaping () -> ImportSessionSnapshot?) { self.current = current }
    var hasAnyWritePermission = true
    var concentration = InsulinConcentration.u100
    var writes = 0
    func refreshAuthorizationStatus() {}
    func save(batch: HealthImportBatch) async throws -> [SampleDTO] {
      try HealthImportPolicy.validate(batch: batch, current: current())
      writes += 1
      return batch.plan.samples.map(\.original)
    }
  }
  private final class ContractProof: DeviceSessionProofProviding {
    func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition { .ready }
    func invalidateHostedProofOperation() {}
    func hostedEnrollment(challenge: SessionChallengeResponse, installationId: String, signedTransactionInfo: String) async throws -> HostedDeviceEnrollment { throw APIClientError.invalidResponse }
    func selfHostedEnrollment(challenge: SessionChallengeResponse, installationId: String) throws -> SelfHostedDeviceEnrollment { throw APIClientError.invalidResponse }
    func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool { false }
    func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool { false }
    func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardRegisteredHostedKey() throws -> Bool { false }
    func releaseHostedProofOperation(requestId: String) -> Bool { true }
    func hostedProofKeyID(requestId: String) throws -> String { "test-key" }
    func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool { keyId == "test-key" }
    func refreshRequest(session: BackendSessionResponse, installationId: String, mode: BackendAccessMode) async throws -> SessionRefreshRequest {
      .init(installationId: installationId, refreshToken: session.refreshToken, requestId: UUID().uuidString, issuedAt: Date(), proof: "test-boundary-proof")
    }
  }
}
