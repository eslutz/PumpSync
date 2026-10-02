import XCTest
import SwiftUI
import UIKit
@testable import PumpSync

@MainActor
final class ImportPreviewTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testMissingCapabilityDoesNotEnablePreview() throws {
        let capabilities = try JSONCodec.decoder.decode(BackendCapabilitiesResponse.self, from: Data(#"{"dataSourceMode":"syntheticDemo"}"#.utf8))
        XCTAssertFalse(capabilities.supportsImportPreview)
    }

    func testProtectedPreviewUsesOnlyPreviewEndpoint() async throws {
        let path = PreviewLocked<String?>(nil)
        let authorization = PreviewLocked<String?>(nil)
        URLProtocolStub.requestHandler = { request in
            path.set(request.url?.path)
            authorization.set(request.value(forHTTPHeaderField: "Authorization"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"syntheticDemo"}"#.utf8))
        }
        let client = PumpSyncAPIClient(baseURL: URL(string: "https://example.com/api")!, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let response = try await client.previewTandem(TandemSyncRequest(tandem: .init(username: "fixture", password: "fixture", region: "us"), minDate: nil, maxDate: nil, timeZoneIdentifier: "UTC"), accessToken: "fixture")
        XCTAssertEqual(path.value, "/api/v1/preview/tandem")
        XCTAssertEqual(authorization.value, "Bearer fixture")
        XCTAssertEqual(response.dataSourceMode, .syntheticDemo)
    }
    func testUnsupportedServiceNeverCallsImportOrPreviewRoute() async throws {
        let calls = PreviewLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            calls.append(request.url!.path)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"dataSourceMode":"syntheticDemo"}"#.utf8))
        }
        let (client, auth) = makeContext()
        let context = snapshot()
        let controller = ImportPreviewController(apiClient: client, authService: auth, currentContext: { context })
        await controller.load(request: request(), context: context, concentration: .u500)
        guard case .failed(let message) = controller.state else { return XCTFail("Expected upgrade message") }
        XCTAssertTrue(message.contains("update"))
        XCTAssertEqual(calls.value, ["/api/v1/capabilities"])
    }

    func testContextChangeDuringCapabilitiesClearsLoadingState() async {
        URLProtocolStub.requestHandler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"dataSourceMode":"syntheticDemo","supportsImportPreview":true}"#.utf8))
        }
        let (client, auth) = makeContext()
        let controller = ImportPreviewController(apiClient: client, authService: auth, currentContext: { nil })
        await controller.load(request: request(), context: snapshot(), concentration: .u100)
        guard case .failed(let message) = controller.state else { return XCTFail("Stale work must clear loading state with actionable feedback") }
        XCTAssertTrue(message.contains("Reconnect"))
    }

    func testRedirectDelegateRejectsCrossOriginBeforeForwarding() async {
        let delegate = SensitiveRequestRedirectGuard()
        let response = HTTPURLResponse(url: URL(string: "https://example.com/api/v1/preview/tandem")!, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://elsewhere.com"])!
        let redirected = await delegate.urlSession(URLSession.shared, task: URLSession.shared.dataTask(with: response.url!), willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://elsewhere.com")!))
        XCTAssertNil(redirected)
    }

    func testAuthenticatedEmptyPreviewRetainsCapturedConcentrationAndClearsOnCancel() async throws {
        URLProtocolStub.requestHandler = { request in
            let body = request.url!.path.hasSuffix("capabilities")
                ? #"{"dataSourceMode":"syntheticDemo","supportsImportPreview":true}"#
                : #"{"samples":[],"effectiveMinDate":"2026-10-01T00:00:00Z","effectiveMaxDate":"2026-10-01T01:00:00Z","dataSourceMode":"syntheticDemo"}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let keychain = SecureKeychainStore(service: "preview-authenticated-\(UUID().uuidString)")
        defer { try? keychain.deleteAll() }
        let store = BackendSessionStore(keychain: keychain)
        try store.save(.init(accessToken: "fixture", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "syntheticDemo"))
        let url = URL(string: "https://example.com/api")!
        let client = PumpSyncAPIClient(baseURL: url, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let auth = AuthService(apiClient: client, configurationStore: .ephemeral(selfHostedBaseURL: url, installationId: "fixture"), sessionStore: store, purpose: .preview, proofProvider: DeviceSessionProofProvider(keychain: keychain))
        let context = try XCTUnwrap(auth.currentImportSnapshot(credentialRevision: 0))
        let controller = ImportPreviewController(apiClient: client, authService: auth, currentContext: { context })
        await controller.load(request: request(), context: context, concentration: .u500)
        guard case .ready(let plan) = controller.state else { return XCTFail("Expected a genuine empty preview") }
        XCTAssertTrue(plan.samples.isEmpty)
        XCTAssertEqual(plan.downloadedRecordCount, 0)
        XCTAssertEqual(plan.concentration, .u500)
        XCTAssertEqual(plan.effectiveMaxDate.timeIntervalSince(plan.effectiveMinDate), 3600)
        controller.cancel()
        guard case .idle = controller.state else { return XCTFail("Payload must clear on close/background") }
    }

    func testPreviewFailuresPreserveHTTPStatusWithoutFallback() async {
        for status in [401, 409, 429] {
            let calls = PreviewLocked<[String]>([])
            URLProtocolStub.requestHandler = { request in
                calls.append(request.url!.path)
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(#"{"code":"preview_error","message":"Fixture"}"#.utf8))
            }
            let (client, _) = makeContext()
            do {
                _ = try await client.previewTandem(request(), accessToken: "fixture")
                XCTFail("Expected HTTP rejection")
            } catch APIClientError.httpStatus(let received, _, _, _) {
                XCTAssertEqual(received, status)
            } catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(calls.value, ["/api/v1/preview/tandem"])
        }
    }

    func testPreviewTimeoutIsNotRetriedAndMalformedPayloadIsRejected() async {
        let calls = PreviewLocked<[String]>([])
        URLProtocolStub.requestHandler = { request in
            calls.append(request.url!.path)
            throw URLError(.timedOut)
        }
        let (client, _) = makeContext()
        client.maxRetryCount = 2
        do { _ = try await client.previewTandem(request(), accessToken: "fixture"); XCTFail("Expected timeout") }
        catch { XCTAssertEqual((error as NSError).code, NSURLErrorTimedOut) }
        XCTAssertEqual(calls.value.count, 1)
        URLProtocolStub.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("not-json".utf8))
        }
        do { _ = try await client.previewTandem(request(), accessToken: "fixture"); XCTFail("Expected malformed payload rejection") }
        catch { XCTAssertTrue(error is DecodingError) }
    }

    func testCaptureTestTargetPreviewRendererEvidence() async throws {
        let date = Date(timeIntervalSince1970: 1_791_158_400)
        let samples = [
            SampleDTO(externalId: "fixture-basal", type: "insulin.basal", value: 0.25, unit: "IU", startAt: date, endAt: date.addingTimeInterval(1800), metadata: [:], source: .init(deviceId: "Test-target sample pump", eventIds: ["fixture-basal"])),
            SampleDTO(externalId: "fixture-bolus", type: "insulin.bolus", value: 1.2, unit: "IU", startAt: date.addingTimeInterval(1800), endAt: date.addingTimeInterval(1800), metadata: [:], source: .init(deviceId: "Test-target sample pump", eventIds: ["fixture-bolus"])),
            SampleDTO(externalId: "fixture-carbs", type: "nutrition.carbohydrates", value: 24, unit: "g", startAt: date.addingTimeInterval(1800), endAt: date.addingTimeInterval(1800), metadata: [:], source: .init(deviceId: "Test-target sample pump", eventIds: ["fixture-carbs"]))
        ]
        let ready = try await rendererController(samples: samples, date: date)
        try await capture(ready, name: "test-target-ready-standard-light", size: CGSize(width: 393, height: 852), text: .large, color: .light)
        try await capture(try await rendererController(samples: samples, date: date), name: "test-target-ready-AX5-dark", size: CGSize(width: 393, height: 852), text: .accessibility5, color: .dark)
        try await capture(try await rendererController(samples: samples, date: date), name: "test-target-ready-AX5-dark-rows", size: CGSize(width: 393, height: 852), text: .accessibility5, color: .dark, scrollOffset: 1000)
        try await capture(try await rendererController(samples: samples, date: date), name: "test-target-ready-iPad", size: CGSize(width: 820, height: 1180), text: .large, color: .light)
        let empty = try await rendererController(samples: [], date: date)
        try await capture(empty, name: "test-target-empty", size: CGSize(width: 393, height: 852), text: .large, color: .light)
        let large = (0..<1000).map { index in
            SampleDTO(externalId: "fixture-\(index)", type: "insulin.bolus", value: 1, unit: "IU", startAt: date.addingTimeInterval(Double(index)), endAt: date.addingTimeInterval(Double(index)), metadata: [:], source: .init(deviceId: "Test-target sample pump", eventIds: ["fixture-\(index)"]))
        }
        let largeController = try await rendererController(samples: large, date: date)
        try await capture(largeController, name: "test-target-large-1000", size: CGSize(width: 393, height: 852), text: .large, color: .light)
    }

    private func rendererController(samples: [SampleDTO], date: Date) async throws -> ImportPreviewController {
        struct RendererResponse: Encodable {
            let samples: [SampleDTO]
            let effectiveMinDate: Date
            let effectiveMaxDate: Date
            let dataSourceMode = "syntheticDemo"
        }
        let data = try JSONCodec.encoder.encode(RendererResponse(samples: samples, effectiveMinDate: date, effectiveMaxDate: date.addingTimeInterval(86400)))
        URLProtocolStub.requestHandler = { request in
            let body = request.url!.path.hasSuffix("capabilities") ? Data(#"{"dataSourceMode":"syntheticDemo","supportsImportPreview":true}"#.utf8) : data
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let keychain = SecureKeychainStore(service: "preview-renderer-\(UUID().uuidString)")
        defer { try? keychain.deleteAll() }
        let store = BackendSessionStore(keychain: keychain)
        try store.save(.init(accessToken: "test-target", expiresAt: .distantFuture, serviceMode: "selfHosted", dataSourceMode: "syntheticDemo"))
        let url = URL(string: "https://example.com/api")!
        let client = PumpSyncAPIClient(baseURL: url, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let auth = AuthService(apiClient: client, configurationStore: .ephemeral(selfHostedBaseURL: url, installationId: "test-target"), sessionStore: store, purpose: .preview, proofProvider: DeviceSessionProofProvider(keychain: keychain))
        let context = try XCTUnwrap(auth.currentImportSnapshot(credentialRevision: 0))
        let controller = ImportPreviewController(apiClient: client, authService: auth, currentContext: { context })
        await controller.load(request: request(), context: context, concentration: .u200)
        guard case .ready = controller.state else { throw PreviewError.connectionRequired }
        return controller
    }

    private func capture(_ controller: ImportPreviewController, name: String, size: CGSize, text: DynamicTypeSize, color: ColorScheme, scrollOffset: CGFloat = 0) async throws {
        let host = UIHostingController(rootView: NavigationStack {
            ImportPreviewView(controller: controller, isSample: true, retry: {})
        }.environment(\.dynamicTypeSize, text).environment(\.colorScheme, color))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        if scrollOffset > 0, let scroll = findScrollView(in: host.view) {
            let maximum = max(0, scroll.contentSize.height - scroll.bounds.height)
            scroll.setContentOffset(CGPoint(x: 0, y: min(scrollOffset, maximum)), animated: false)
            try await Task.sleep(for: .milliseconds(350))
        }
        guard case .ready = controller.state else { return XCTFail("Renderer lost ready data before capture") }
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findScrollView(in: child) { return scroll }
        }
        return nil
    }

    private func makeContext() -> (PumpSyncAPIClient, AuthService) {
        let url = URL(string: "https://example.com/api")!
        let client = PumpSyncAPIClient(baseURL: url, urlSession: URLProtocolStub.makeSession(), maxRetryCount: 0)
        let configuration = BackendConfigurationStore.ephemeral(selfHostedBaseURL: url, installationId: "preview-fixture")
        let auth = AuthService(apiClient: client, configurationStore: configuration, purpose: .preview, proofProvider: DeviceSessionProofProvider(keychain: .init(service: "preview-fixture")))
        return (client, auth)
    }
    private func snapshot() -> ImportSessionSnapshot {
        .init(backendIdentity: "https://example.com/api", configurationRevision: 0, credentialRevision: 0, sessionFamilyId: "fixture", dataSourceMode: .syntheticDemo)
    }
    private func request() -> TandemSyncRequest {
        .init(tandem: .init(username: "fixture", password: "fixture", region: "us"), minDate: nil, maxDate: nil, timeZoneIdentifier: "UTC")
    }

}

private final class PreviewLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func set(_ value: Value) { lock.withLock { stored = value } }
}

private extension PreviewLocked where Value == [String] {
    func append(_ value: String) { var current = self.value; current.append(value); set(current) }
}
