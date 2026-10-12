import XCTest
@testable import PumpSync

@MainActor
final class PreviewBoundaryRegressionTests: XCTestCase {
    override func tearDown() { URLProtocolStub.requestHandler = nil; super.tearDown() }

    func testInMemorySessionExpiredTokenIsNotSignedIn() async {
        let (auth, _) = makeAuth(expired: true)
        await auth.connectSelfHosted()
        XCTAssertFalse(auth.isSignedIn, "In-memory persistence must not make expired tokens valid")
    }

    func testInMemorySessionRenewalUsesRefreshInsteadOfExpiredAccessToken() async throws {
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
        let concentration = InsulinConcentrationStore(defaults: defaults)
        let preview = RealImportPreviewSession(apiClient: api, authService: auth, credentialStore: credentials, metadataStore: .init(defaults: defaults), concentrationStore: concentration)
        await preview.load()
        XCTAssertEqual(paths.value.count, 2)
        concentration.concentration = .u500
        preview.controller.suspend()
        await preview.loadIfNeeded()
        XCTAssertEqual(paths.value.count, 2, "Returning to the loaded screen must not fetch a new window")
        guard case .ready(let retained) = preview.controller.state else { return XCTFail("Expected the loaded snapshot") }
        XCTAssertEqual(retained.concentration, .u100, "The displayed conversion setting belongs to the retained snapshot")
        credentials.invalidateValidation()
        await preview.load()
        XCTAssertEqual(paths.value.count, 2, "Revalidation is required before another preview download")
        guard case .failed(let message) = preview.controller.state else { return XCTFail("Expected Settings revalidation feedback") }
        XCTAssertTrue(message.contains("Settings"))
    }

    func testRealPreviewReenrollmentCapturesFreshContextBeforeDownload() async throws {
        let keychain = SecureKeychainStore(service: "real-preview-reenrollment-\(UUID().uuidString)")
        defer { try? keychain.deleteAll() }
        let credentials = TandemCredentialStore(keychain: keychain)
        try credentials.saveValidated(.init(username: "real-fixture", password: "real-fixture", region: "us"))
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        var enrollments = 0
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "real-fixture"),
            currentEntitlementJWS: { "unused" }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse },
            createSelfHostedSession: { _ in
                enrollments += 1
                return BackendSessionResponse(accessToken: enrollments == 1 ? "expired-fixture" : "fresh-fixture", expiresAt: enrollments == 1 ? .distantPast : .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: enrollments == 1 ? "expired-family" : "fresh-family", refreshToken: "fixture", refreshTokenExpiresAt: enrollments == 1 ? .distantPast : .distantFuture, refreshTokenAbsoluteExpiresAt: enrollments == 1 ? .distantPast : .distantFuture)
            }, proofProvider: PreviewBoundaryProof())
        await auth.connectSelfHosted()
        let original = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: credentials.revision))
        let suite = "real-preview-reenrollment-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let downloads = BoundaryLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            if request.url!.path.hasSuffix("capabilities") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"dataSourceMode":"tandemSource","supportsImportPreview":true}"#.utf8))
            }
            downloads.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"tandemSource"}"#.utf8))
        }
        let metadata = SyncMetadataStore(defaults: defaults)
        let prior = metadata.metadata
        let preview = RealImportPreviewSession(apiClient: api, authService: auth, credentialStore: credentials, metadataStore: metadata, concentrationStore: .init(defaults: defaults))
        await preview.load()
        guard case .ready(let plan) = preview.controller.state else { return XCTFail("Fresh reenrollment should enable one preview download") }
        XCTAssertEqual(enrollments, 2)
        XCTAssertEqual(downloads.value, ["Bearer fresh-fixture"])
        XCTAssertNotEqual(plan.context.connectionId, original.connectionId)
        XCTAssertEqual(plan.context, auth.currentImportSnapshot(credentialRevision: credentials.revision))
        XCTAssertEqual(metadata.metadata, prior)
    }

    func testRealPreviewUsesOnlyMatchingDurableAccountAndBackendCursorWithoutMutatingMetadata() async throws {
        let keychain = SecureKeychainStore(service: "preview-cursor-owner-\(UUID().uuidString)")
        defer { try? keychain.deleteAll() }
        let credentials = TandemCredentialStore(keychain: keychain)
        try credentials.saveValidated(.init(username: "real-fixture", password: "fixture", region: "us"))
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://real-preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let response = BackendSessionResponse(accessToken: "fixture", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource")
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "preview-owner"), currentEntitlementJWS: { throw APIClientError.invalidResponse }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse }, createSelfHostedSession: { _ in response }, proofProvider: PreviewBoundaryProof())
        await auth.connectSelfHosted()
        let suite = "preview-cursor-owner-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let metadata = SyncMetadataStore(defaults: defaults)
        metadata.setInitialImportRange(.pastTwoDays)
        let cursor = Date(timeIntervalSince1970: 100)
        let minima = BoundaryLocked<[Date]>([])
        URLProtocolStub.requestHandler = { request in
            if request.url!.path.hasSuffix("capabilities") {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"dataSourceMode":"tandemSource","supportsImportPreview":true}"#.utf8))
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Self.bodyString(request).utf8)) as? [String: Any])
            let minimum = try XCTUnwrap(ISO8601DateFormatter().date(from: XCTUnwrap(body["minDate"] as? String)))
            minima.update { $0.append(minimum) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"tandemSource"}"#.utf8))
        }
        let preview = RealImportPreviewSession(apiClient: api, authService: auth, credentialStore: credentials, metadataStore: metadata, concentrationStore: .init(defaults: defaults))
        let currentAccount = try XCTUnwrap(credentials.accountId)
        for owner in [TandemSyncOwner(accountId: currentAccount, backendIdentity: "https://real-preview.example/api"), TandemSyncOwner(accountId: UUID(), backendIdentity: "https://real-preview.example/api"), TandemSyncOwner(accountId: currentAccount, backendIdentity: "https://other.example/api")] {
            metadata.recordSuccess(sampleCount: 4, importedCount: 3, completedAt: Date(), watermark: cursor, owner: owner)
            let before = defaults.data(forKey: "sync-metadata")
            await preview.load()
            guard case .ready = preview.controller.state else { return XCTFail("Expected real preview") }
            XCTAssertEqual(minima.value.last, owner.accountId == currentAccount && owner.backendIdentity == "https://real-preview.example/api" ? cursor : InitialImportRange.pastTwoDays.minimumDate(relativeTo: Date()))
            XCTAssertEqual(defaults.data(forKey: "sync-metadata"), before)
        }
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
        let controller = ImportPreviewController(apiClient: api, authService: auth, currentContext: { context })
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

    func testRetainedInspectionSurvivesRenewalButRejectsChangedOwnership() async throws {
        let (auth, api) = makeAuth(expired: false)
        await auth.connectSelfHosted()
        let original = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        var current: ImportSessionSnapshot? = original
        let paths = BoundaryLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            paths.append(request.url!.path)
            return request.url!.path.hasSuffix("capabilities") ? Self.capabilities(request) : Self.emptyResponse(request)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, currentContext: { current })
        await controller.load(request: previewRequest(), context: original, concentration: .u200)
        current = .init(backendIdentity: original.backendIdentity, configurationRevision: original.configurationRevision, credentialRevision: 0, connectionId: UUID(), dataSourceMode: .tandemSource)
        controller.suspend()
        controller.validateSnapshot()
        guard case .ready(let retained) = controller.state else { return XCTFail("Same-account renewal must retain inspection") }
        XCTAssertEqual(retained.context, original)
        XCTAssertEqual(paths.value, ["/api/v1/capabilities", "/api/v1/preview/tandem"], "Restoring loaded inspection makes no request")

        current = .init(backendIdentity: original.backendIdentity, configurationRevision: original.configurationRevision, credentialRevision: 1, connectionId: UUID(), dataSourceMode: .tandemSource)
        controller.validateSnapshot()
        guard case .failed = controller.state else { return XCTFail("Changed pump credentials must invalidate cached records") }
        XCTAssertTrue(controller.recordsNewestFirst.isEmpty)
        XCTAssertNil(controller.loadedAt)
    }

    func testRetainedInspectionClearsWhenConnectionIsRemoved() async throws {
        let (auth, api) = makeAuth(expired: false)
        await auth.connectSelfHosted()
        let original = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        var current: ImportSessionSnapshot? = original
        URLProtocolStub.requestHandler = { request in
            request.url!.path.hasSuffix("capabilities") ? Self.capabilities(request) : Self.emptyResponse(request)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, currentContext: { current })
        await controller.load(request: previewRequest(), context: original, concentration: .u100)
        current = nil
        controller.validateSnapshot()
        guard case .failed = controller.state else { return XCTFail("A disconnected inspection must clear its snapshot") }
    }

    func testSuspendingRefreshKeepsSnapshotAndRejectsLateResponse() async throws {
        let (auth, api) = makeAuth(expired: false)
        await auth.connectSelfHosted()
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        URLProtocolStub.requestHandler = { request in
            request.url!.path.hasSuffix("capabilities") ? Self.capabilities(request) : Self.emptyResponse(request)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, currentContext: { context })
        await controller.load(request: previewRequest(), context: context, concentration: .u200)
        let loadedAt = try XCTUnwrap(controller.loadedAt)
        let started = BoundaryLocked(false)
        let delivered = BoundaryLocked(false)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        URLProtocolStub.requestHandler = { request in
            if request.url!.path.hasSuffix("capabilities") { return Self.capabilities(request) }
            started.update { $0 = true }
            _ = gate.wait(timeout: .now() + 5)
            delivered.update { $0 = true }
            return Self.emptyResponse(request)
        }
        let refresh = Task { await controller.load(request: previewRequest(), context: context, concentration: .u500) }
        await waitUntil { started.value }
        XCTAssertTrue(controller.isRefreshing)
        guard case .ready(let visible) = controller.state else { return XCTFail("Refresh must keep records visible") }
        XCTAssertEqual(visible.concentration, .u200)
        controller.suspend()
        XCTAssertFalse(controller.isRefreshing)
        gate.signal()
        await refresh.value
        await waitUntil { delivered.value }
        guard case .ready(let retained) = controller.state else { return XCTFail("Suspending refresh must retain the original snapshot") }
        XCTAssertEqual(retained.concentration, .u200)
        XCTAssertEqual(controller.loadedAt, loadedAt)
        XCTAssertNil(controller.refreshError)
    }



    func testExpiredInspectionRefreshesRotatingFamilyBeforeDownloading() async throws {
        let (auth, api) = makeAuth(expired: true)
        await auth.connectSelfHosted()
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        let refreshedData = try JSONCodec.encoder.encode(BackendSessionResponse(accessToken: "valid-preview-token", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "rotated-preview-family", refreshToken: "rotated-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture))
        let paths = BoundaryLocked<[String]>([])
        let previewAuthorization = BoundaryLocked<String?>(nil)
        URLProtocolStub.requestHandler = { request in
            paths.append(request.url!.path)
            if request.url!.path.hasSuffix("capabilities") { return Self.capabilities(request) }
            if request.url!.path.hasSuffix("refresh") { return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, refreshedData) }
            previewAuthorization.update { $0 = request.value(forHTTPHeaderField: "Authorization") }
            return Self.emptyResponse(request)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, currentContext: { auth.operationImportSnapshot(credentialRevision: 0) })
        await controller.load(request: previewRequest(), context: context, concentration: .u100)
        guard case .ready = controller.state else { return XCTFail("Rotating-family renewal must allow preview") }
        XCTAssertEqual(paths.value, ["/api/v1/capabilities", "/api/v1/session/refresh", "/api/v1/preview/tandem"])
        XCTAssertEqual(previewAuthorization.value, "Bearer valid-preview-token")
    }

    func testExpiredRealPreviewRotatesFamilyAndRetainsCapturedContext() async throws {
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://real-preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let configuration = BackendConfigurationStore.ephemeral(selfHostedBaseURL: api.baseURL, installationId: "real-preview")
        let keychain = SecureKeychainStore(service: "real-preview-rotation-\(UUID().uuidString)")
        defer { try? keychain.deleteAll() }
        let store = BackendSessionStore(keychain: keychain)
        let expired = BackendSessionResponse(accessToken: "expired-real", expiresAt: .distantPast, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "old-real-family", refreshToken: "old-real-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
        try store.save(expired)
        let auth = AuthService(apiClient: api, configurationStore: configuration, sessionStore: store, purpose: .liveImport, currentEntitlementJWS: { throw APIClientError.invalidResponse }, createSubscriptionSession: { _ in throw APIClientError.invalidResponse }, createSelfHostedSession: { _ in XCTFail("Ordinary refresh must not enroll"); throw APIClientError.invalidResponse }, proofProvider: PreviewBoundaryProof())
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 4))
        let refreshed = BackendSessionResponse(accessToken: "new-real", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "new-real-family", refreshToken: "new-real-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
        let data = try JSONCodec.encoder.encode(refreshed)
        let paths = BoundaryLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            paths.append(request.url!.path)
            let body: Data
            if request.url!.path.hasSuffix("capabilities") {
                body = Data(#"{"dataSourceMode":"tandemSource","supportsImportPreview":true}"#.utf8)
            } else if request.url!.path.hasSuffix("refresh") { body = data }
            else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-real")
                body = Data(#"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"tandemSource"}"#.utf8)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, currentContext: { auth.operationImportSnapshot(credentialRevision: 4) })
        await controller.load(request: previewRequest(), context: context, concentration: .u100)
        guard case .ready(let plan) = controller.state else { return XCTFail("Real preview must survive ordinary rotating refresh") }
        XCTAssertEqual(plan.context, context)
        XCTAssertEqual(auth.session, refreshed)
        XCTAssertEqual(paths.value, ["/api/v1/capabilities", "/api/v1/session/refresh", "/api/v1/preview/tandem"])
        XCTAssertEqual(try store.loadConnection(binding: XCTUnwrap(auth.connectionBinding))?.identity.id, context.connectionId)
    }

    func testReenrollmentIntoNewFamilyUsesFreshContextForInspection() async throws {
        let expired = BackendSessionResponse(accessToken: "expired", expiresAt: .distantPast, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "old-family", refreshToken: "expired", refreshTokenExpiresAt: .distantPast, refreshTokenAbsoluteExpiresAt: .distantPast)
        let replacement = session(expired: false)
        let api = PumpSyncAPIClient(baseURL: URL(string: "https://preview.example/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        var enrollments = 0
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "preview-only"), purpose: .liveImport, currentEntitlementJWS: { "unused" }, createSubscriptionSession: { _ in replacement }, createSelfHostedSession: { _ in enrollments += 1; return enrollments == 1 ? expired : replacement }, proofProvider: PreviewBoundaryProof())
        await auth.connectSelfHosted()
        let context = try XCTUnwrap(auth.operationImportSnapshot(credentialRevision: 0))
        let paths = BoundaryLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            paths.append(request.url!.path)
            return request.url!.path.hasSuffix("capabilities") ? Self.capabilities(request) : Self.emptyResponse(request)
        }
        let controller = ImportPreviewController(apiClient: api, authService: auth, currentContext: { auth.operationImportSnapshot(credentialRevision: 0) })
        await controller.load(request: previewRequest(), context: context, concentration: .u100)
        guard case .ready(let plan) = controller.state else { return XCTFail("Inspection must recapture the renewed connection") }
        XCTAssertNotEqual(plan.context.connectionId, context.connectionId)
        XCTAssertEqual(plan.context, auth.operationImportSnapshot(credentialRevision: 0))
        XCTAssertEqual(paths.value, ["/api/v1/capabilities", "/api/v1/preview/tandem"])
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
        let controller = ImportPreviewController(apiClient: api, authService: auth, diagnostics: diagnostics, currentContext: { nil })
        await controller.load(request: previewRequest(), context: context, concentration: .u100)
        XCTAssertTrue(diagnostics.entries.allSatisfy { $0.message?.contains("purpose=real") == true })
        XCTAssertFalse(diagnostics.entries.contains { $0.message?.contains("sample-only") == true })
        XCTAssertFalse(diagnostics.entries.contains { $0.message?.contains("2026") == true })
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
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"dataSourceMode":"tandemSource","supportsImportPreview":true}"#.utf8))
    }
    private nonisolated static func emptyResponse(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"tandemSource"}"#.utf8))
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
        let auth = AuthService(apiClient: api, configurationStore: .ephemeral(selfHostedBaseURL: api.baseURL, installationId: "preview-only"), purpose: .liveImport, currentEntitlementJWS: { "unused" }, createSubscriptionSession: { _ in response }, createSelfHostedSession: { _ in response }, proofProvider: PreviewBoundaryProof())
        return (auth, api)
    }

    private func session(expired: Bool) -> BackendSessionResponse {
        .init(accessToken: expired ? "expired-preview-token" : "valid-preview-token", expiresAt: expired ? .distantPast : .distantFuture, serviceMode: "selfHosted", dataSourceMode: "tandemSource", protocolVersion: 3, sessionFamilyId: "preview-family", refreshToken: "preview-refresh", refreshTokenExpiresAt: .distantFuture, refreshTokenAbsoluteExpiresAt: .distantFuture)
    }
}

@MainActor
private final class PreviewBoundaryProof: DeviceSessionProofProviding {
  func hostedRecoveryDisposition() throws -> HostedProofRecoveryDisposition { .ready }
  func invalidateHostedProofOperation() {}
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
    func hostedProofKeyID(requestId: String) throws -> String { "app-attest-key" }
    func hostedRegisteredKeyMatches(_ keyId: String) throws -> Bool { keyId == "app-attest-key" }
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
