import XCTest
@testable import PumpSync

@MainActor
final class PreviewBoundaryRegressionTests: XCTestCase {
    override func tearDown() { URLProtocolStub.requestHandler = nil; super.tearDown() }

    func testInMemoryDemoExpiredTokenIsNotSignedIn() async {
        let (auth, _) = makeAuth(expired: true)
        await auth.connectSelfHosted()
        XCTAssertFalse(auth.isSignedIn, "In-memory persistence must not make expired tokens valid")
    }

    func testInMemoryDemoRenewalUsesRefreshInsteadOfExpiredAccessToken() async throws {
        let refreshed = session(expired: false)
        let data = try JSONCodec.encoder.encode(refreshed)
        let paths = BoundaryLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            paths.append(request.url!.path)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let (auth, _) = makeAuth(expired: true)
        await auth.connectSelfHosted()
        let token = await auth.accessTokenRecoveringIfNeeded()
        XCTAssertEqual(token, "valid-preview-token")
        XCTAssertEqual(paths.value, ["/api/v1/session/refresh"])
        XCTAssertEqual(auth.session?.sessionFamilyId, "preview-family")
    }

    func testRealReloadRequiresCurrentCredentialValidation() async throws {
        let keychain = SecureKeychainStore(service: "real-preview-validation-\(UUID().uuidString)")
        defer { try? keychain.deleteAll() }
        let credentials = TandemCredentialStore(keychain: keychain)
        try credentials.saveValidated(.init(username: "real-fixture", password: "real-fixture", region: "us"))
        let response = BackendSessionResponse(accessToken: "real-fixture", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource")
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "real-fixture"), currentEntitlementJWS: { "unused" }, createSubscriptionSession: { _ in response }, createSelfHostedSession: { _ in response }, proofProvider: PreviewBoundaryProof())
        await auth.connectSelfHosted()
        let suite = "real-preview-validation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let paths = BoundaryLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            paths.append(request.url!.path)
            let body = request.url!.path.hasSuffix("capabilities") ? #"{"dataSourceMode":"tandemSource","supportsImportPreview":true}"# : #"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"tandemSource"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let preview = RealImportPreviewSession(apiClient: api, authService: auth, credentialStore: credentials, metadataStore: .init(defaults: defaults), concentrationStore: .init(defaults: defaults))
        await preview.load()
        XCTAssertEqual(paths.value.count, 2)
        credentials.invalidateValidation()
        await preview.load()
        XCTAssertEqual(paths.value.count, 2, "Revalidation is required before another preview download")
        guard case .failed(let message) = preview.controller.state else { return XCTFail("Expected Settings revalidation feedback") }
        XCTAssertTrue(message.contains("Settings"))
    }

    func testCanceledAndReplacedRequestsCannotPublishLateResults() async throws {
        let (auth, api) = makeAuth(expired: false)
        await auth.connectSelfHosted()
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        let started = BoundaryLocked(false)
        let completed = BoundaryLocked(false)
        let gate = DispatchSemaphore(value: 0)
        let previewCount = BoundaryLocked(0)
        URLProtocolStub.requestHandler = { request in
            if request.url!.path.hasSuffix("capabilities") { return Self.capabilities(request) }
            var number = 0
            previewCount.update { $0 += 1; number = $0 }
            if number == 1 {
                started.update { $0 = true }
                _ = gate.wait(timeout: .now() + 5)
                completed.update { $0 = true }
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data(#"{"code":"fixture","message":"Late failure"}"#.utf8))
            }
            return Self.emptyResponse(request)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, purpose: .sample, currentContext: { context })
        let old = Task { await controller.load(request: previewRequest(), context: context, concentration: .u500) }
        await waitUntil { started.value }
        controller.cancel()
        guard case .idle = controller.state else { return XCTFail("Canceled work must clear immediately") }
        let replacement = Task { await controller.load(request: previewRequest(), context: context, concentration: .u100) }
        gate.signal()
        await old.value
        await replacement.value
        XCTAssertTrue(completed.value, "Old actual request delivered its late failure")
        guard case .ready(let plan) = controller.state else { return XCTFail("Replacement must remain ready") }
        XCTAssertEqual(plan.concentration, .u100)
        XCTAssertEqual(previewCount.value, 2)
    }

    func testBackgroundCloseDuringActualPreviewRequestRejectsLatePayload() async throws {
        let (auth, api) = makeAuth(expired: false)
        let demo = DemoPreviewSession(apiClient: api, authService: auth, diagnostics: nil)
        await demo.connect()
        let started = BoundaryLocked(false)
        let completed = BoundaryLocked(false)
        let gate = DispatchSemaphore(value: 0)
        URLProtocolStub.requestHandler = { request in
            if request.url!.path.hasSuffix("capabilities") { return Self.capabilities(request) }
            if request.url!.path.hasSuffix("validate") { return Self.validatedResponse(request) }
            started.update { $0 = true }
            _ = gate.wait(timeout: .now() + 5)
            completed.update { $0 = true }
            return Self.emptyResponse(request)
        }
        try await demo.validate(credentials: .init(username: "sample-only", password: "sample-only", region: "us"))
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: demo.credentialRevision))
        let operation = Task { await demo.controller.load(request: previewRequest(), context: context, concentration: .u100) }
        await waitUntil { started.value }
        demo.close() // The production scene/background and dismissal boundary.
        gate.signal()
        await operation.value
        XCTAssertTrue(completed.value)
        XCTAssertNil(demo.credentials)
        XCTAssertNil(auth.session)
        guard case .idle = demo.controller.state else { return XCTFail("Late payload must not resurrect a closed preview") }
    }

    func testCloseDuringActualEnrollmentRejectsLateSession() async throws {
        let data = try JSONCodec.encoder.encode(session(expired: false))
        let started = BoundaryLocked(false)
        let gate = DispatchSemaphore(value: 0)
        URLProtocolStub.requestHandler = { request in
            if request.url!.path.hasSuffix("challenge") { return Self.challengeResponse(request) }
            started.update { $0 = true }
            _ = gate.wait(timeout: .now() + 5)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let demo = productionDemo()
        let operation = Task { await demo.connect() }
        await waitUntil { started.value }
        demo.close()
        gate.signal()
        await operation.value
        XCTAssertNil(demo.authService.session)
        XCTAssertNil(demo.credentials)
    }

    func testConnectedDemoLifecyclePreservesActualLiveNamespaceBytes() async throws {
        let defaults = UserDefaults.standard
        let keys = ["backend.mode", "backend.selfHostedBaseURL", "backend.installationId", "insulinConcentration", "sync-metadata", "imported-sample-ledger"]
        let defaultsBackup = keys.map { ($0, defaults.object(forKey: $0)) }
        let liveKeychain = SecureKeychainStore(service: "dev.ericslutz.PumpSync")
        let accounts = ["backend.session.current", "tandem-source-credentials", "tandem-source-credential-validation", "imported-sample-ledger-hmac-key"]
        let keychainBackup = try accounts.map { ($0, try liveKeychain.readData(account: $0)) }
        defer {
            for (key, value) in defaultsBackup {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            for (account, data) in keychainBackup {
                if let data { try? liveKeychain.writeData(data, account: account) } else { try? liveKeychain.delete(account: account) }
            }
        }
        let liveConfiguration = BackendConfigurationStore()
        liveConfiguration.mode = .selfHosted
        liveConfiguration.selfHostedBaseURLString = "https://real-fixture.example/api"
        let realCredentials = TandemCredentialStore(keychain: liveKeychain)
        try realCredentials.saveValidated(.init(username: "real-only-account", password: "real-only-secret", region: "us"))
        let realSession = BackendSessionResponse(accessToken: "real-only-token", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource")
        try BackendSessionStore(keychain: liveKeychain).save(realSession)
        let liveConcentration = InsulinConcentrationStore()
        liveConcentration.concentration = .u500
        let liveMetadata = SyncMetadataStore()
        liveMetadata.recordSuccess(sampleCount: 4, importedCount: 3, completedAt: Date(timeIntervalSince1970: 123456), watermark: Date(timeIntervalSince1970: 123000))
        let liveLedger = ImportedSampleLedger(keychain: liveKeychain)
        try liveLedger.recordImported([SampleDTO(externalId: "real-existing-record", type: "insulin.bolus", value: 1, unit: "IU", startAt: Date(), endAt: Date(), metadata: [:], source: .init(deviceId: "real-existing-source", eventIds: []))])
        let beforeDefaults = NSDictionary(dictionary: Dictionary(uniqueKeysWithValues: keys.compactMap { key in defaults.object(forKey: key).map { (key, $0) } }))
        let beforeKeychain = try accounts.map { try liveKeychain.readData(account: $0) }
        func assertLiveUnchanged() throws {
            let after = NSDictionary(dictionary: Dictionary(uniqueKeysWithValues: keys.compactMap { key in defaults.object(forKey: key).map { (key, $0) } }))
            XCTAssertEqual(after, beforeDefaults)
            XCTAssertEqual(try accounts.map { try liveKeychain.readData(account: $0) }, beforeKeychain)
            XCTAssertEqual(liveConcentration.concentration, .u500)
            XCTAssertEqual(try realCredentials.load(), .init(username: "real-only-account", password: "real-only-secret", region: "us"))
        }
        let sessionData = try JSONCodec.encoder.encode(session(expired: false))
        let bodies = BoundaryLocked<[String]>([])
        let fails = BoundaryLocked(false)
        URLProtocolStub.requestHandler = { request in
            bodies.append(Self.bodyString(request))
            switch request.url!.path {
            case "/api/v1/session/challenge": return Self.challengeResponse(request)
            case "/api/v1/self-host/session": return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, sessionData)
            case "/api/v1/capabilities": return Self.capabilities(request)
            case "/api/v1/tandem/credentials/validate": return Self.validatedResponse(request)
            case "/api/v1/preview/tandem":
                if fails.value { return (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data(#"{"code":"fixture","message":"Unavailable"}"#.utf8)) }
                return Self.emptyResponse(request)
            default: throw URLError(.unsupportedURL)
            }
        }
        let demo = productionDemo()
        await demo.connect()
        XCTAssertTrue(demo.authService.isSignedIn)
        try assertLiveUnchanged()
        try await demo.validate(credentials: .init(username: "sample-only", password: "sample-only", region: "us"))
        try assertLiveUnchanged()
        let context = try XCTUnwrap(demo.authService.operationImportSnapshot(credentialRevision: demo.credentialRevision))
        await demo.controller.load(request: previewRequest(), context: context, concentration: .u100)
        guard case .ready = demo.controller.state else { return XCTFail("Expected sample preview") }
        try assertLiveUnchanged()
        fails.update { $0 = true }
        await demo.controller.load(request: previewRequest(), context: context, concentration: .u200)
        guard case .failed = demo.controller.state else { return XCTFail("Expected controlled failure") }
        try assertLiveUnchanged()
        fails.update { $0 = false }
        await demo.controller.load(request: previewRequest(), context: context, concentration: .u500)
        try assertLiveUnchanged()
        demo.close()
        try assertLiveUnchanged()
        XCTAssertFalse(bodies.value.contains { $0.contains("real-only") })
        XCTAssertTrue(bodies.value.contains { $0.contains("sample-only") })
        let factorySession = try DemoPreviewSession.make()
        factorySession.close()
        try assertLiveUnchanged()
    }

    func testExpiredDemoPreviewRefreshesSameFamilyBeforeDownloading() async throws {
        let (auth, api) = makeAuth(expired: true)
        await auth.connectSelfHosted()
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        let refreshedData = try JSONCodec.encoder.encode(session(expired: false))
        let paths = BoundaryLocked<[String]>([])
        let previewAuthorization = BoundaryLocked<String?>(nil)
        URLProtocolStub.requestHandler = { request in
            paths.append(request.url!.path)
            if request.url!.path.hasSuffix("capabilities") { return Self.capabilities(request) }
            if request.url!.path.hasSuffix("refresh") { return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshedData) }
            previewAuthorization.update { $0 = request.value(forHTTPHeaderField: "Authorization") }
            return Self.emptyResponse(request)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, purpose: .sample, currentContext: { auth.operationImportSnapshot(credentialRevision: 0) })
        await controller.load(request: previewRequest(), context: context, concentration: .u100)
        guard case .ready = controller.state else { return XCTFail("Same-family renewal must allow preview") }
        XCTAssertEqual(paths.value, ["/api/v1/capabilities", "/api/v1/session/refresh", "/api/v1/preview/tandem"])
        XCTAssertEqual(previewAuthorization.value, "Bearer valid-preview-token")
    }

    func testReenrollmentIntoNewFamilyRejectsCapturedPreviewWithActionableFeedback() async throws {
        let expired = BackendSessionResponse(accessToken: "expired", expiresAt: .distantPast, serviceMode: "selfHosted", dataSourceMode: "syntheticDemo", protocolVersion: 3, sessionFamilyId: "old-family", refreshToken: "expired", refreshTokenExpiresAt: .distantPast, refreshTokenAbsoluteExpiresAt: .distantPast)
        let replacement = session(expired: false)
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        var enrollments = 0
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "preview-only"), purpose: .preview, currentEntitlementJWS: { "unused" }, createSubscriptionSession: { _ in replacement }, createSelfHostedSession: { _ in enrollments += 1; return enrollments == 1 ? expired : replacement }, proofProvider: PreviewBoundaryProof())
        await auth.connectSelfHosted()
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        let paths = BoundaryLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in paths.append(request.url!.path); return Self.capabilities(request) }
        let controller = ImportPreviewController(apiClient: api, authService: auth, purpose: .sample, currentContext: { auth.operationImportSnapshot(credentialRevision: 0) })
        await controller.load(request: previewRequest(), context: context, concentration: .u100)
        guard case .failed(let message) = controller.state else { return XCTFail("New family requires a new preview") }
        XCTAssertTrue(message.contains("Reconnect"))
        XCTAssertEqual(paths.value, ["/api/v1/capabilities"])
        XCTAssertEqual(enrollments, 2)
    }

    func testSummaryDiagnosticsIdentifyPurposeWithoutSamplePayload() async throws {
        let suite = "preview-summary-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let diagnostics = DiagnosticsLogStore(defaults: defaults)
        let (auth, api) = makeAuth(expired: false)
        await auth.connectSelfHosted()
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        URLProtocolStub.requestHandler = { request in Self.capabilities(request) }
        let controller = ImportPreviewController(apiClient: api, authService: auth, purpose: .sample, diagnostics: diagnostics, currentContext: { nil })
        await controller.load(request: previewRequest(), context: context, concentration: .u100)
        XCTAssertTrue(diagnostics.entries.allSatisfy { $0.message?.contains("purpose=sample") == true })
        XCTAssertFalse(diagnostics.entries.contains { $0.message?.contains("sample-only") == true })
        XCTAssertFalse(diagnostics.entries.contains { $0.message?.contains("2026") == true })
    }

    private func productionDemo() -> DemoPreviewSession {
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "isolated-preview-identity"), purpose: .preview, proofProvider: PreviewBoundaryProof())
        return DemoPreviewSession(apiClient: api, authService: auth, diagnostics: nil)
    }
    private func previewRequest() -> TandemSyncRequest {
        .init(tandem: .init(username: "sample-only", password: "sample-only", region: "us"), minDate: nil, maxDate: nil, timeZoneIdentifier: "UTC")
    }
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Suspended request never started")
    }
    private nonisolated static func capabilities(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"dataSourceMode":"syntheticDemo","supportsImportPreview":true}"#.utf8))
    }
    private nonisolated static func emptyResponse(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"syntheticDemo"}"#.utf8))
    }
    private nonisolated static func validatedResponse(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"validated":true}"#.utf8))
    }
    private nonisolated static func challengeResponse(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"protocolVersion":3,"proofKind":"secureEnclaveP256","challengeToken":"test-target","expiresAt":"2099-01-01T00:00:00Z"}"#.utf8))
    }
    private nonisolated static func bodyString(_ request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return String(decoding: result, as: UTF8.self)
    }

    private func makeAuth(expired: Bool) -> (AuthService, PumpSyncAPIClient) {
        let response = session(expired: expired)
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "preview-only"), purpose: .preview, currentEntitlementJWS: { "unused" }, createSubscriptionSession: { _ in response }, createSelfHostedSession: { _ in response }, proofProvider: PreviewBoundaryProof())
        return (auth, api)
    }

    private func session(expired: Bool) -> BackendSessionResponse {
        .init(accessToken: expired ? "expired-preview-token" : "valid-preview-token", expiresAt: expired ? .distantPast : .distantFuture, serviceMode: "selfHosted", dataSourceMode: "syntheticDemo", protocolVersion: 3, sessionFamilyId: "preview-family", refreshToken: "preview-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
    }
}

@MainActor
private final class PreviewBoundaryProof: DeviceSessionProofProviding {
    func hostedEnrollment(challenge: SessionChallengeResponse, installationId: String, signedTransactionInfo: String) async throws -> HostedDeviceEnrollment {
        .init(requestId: "fixture", issuedAt: Date(), challengeToken: challenge.challengeToken, keyId: "fixture", proofKind: "attestation", proof: "test-target")
    }
    func markHostedEnrollmentSubmissionStarted(keyId: String, requestId: String) throws -> Bool { true }
    func markHostedEnrollmentRegistered(keyId: String, requestId: String) throws -> Bool { true }
    func resolveRejectedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardUnsubmittedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardDefinitivelyFailedHostedEnrollment(keyId: String, requestId: String) throws -> Bool { false }
    func discardRegisteredHostedKey() throws -> Bool { false }
    func releaseHostedProofOperation(requestId: String) -> Bool { true }
    func selfHostedEnrollment(challenge: SessionChallengeResponse, installationId: String) throws -> SelfHostedDeviceEnrollment {
        .init(requestId: "fixture", issuedAt: Date(), challengeToken: challenge.challengeToken, publicKey: "test-target", signature: "test-target")
    }
    func refreshRequest(session: BackendSessionResponse, installationId: String, mode: BackendAccessMode) async throws -> SessionRefreshRequest {
        .init(installationId: installationId, refreshToken: session.refreshToken, requestId: "fixture", issuedAt: Date(), proof: "test-target")
    }
}

private final class BoundaryLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}
private extension BoundaryLocked where Value == [String] {
    func append(_ value: String) { update { $0.append(value) } }
}
