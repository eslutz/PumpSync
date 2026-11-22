import XCTest
import SwiftUI
import UIKit
@testable import PumpSync

@MainActor
final class ImportPreviewTests: XCTestCase {
    private var source: DirectImportTestSource?

    func testLoadedRecordsSurviveSceneBackgroundAndResume() async throws {
        let date = Date(timeIntervalSince1970: 1_791_158_400)
        let sample = SampleDTO(externalId: "retained", type: "insulin.bolus", value: 1.2, unit: "IU", startAt: date, endAt: date, metadata: [:], source: .init(deviceId: "Test pump", eventIds: ["retained"]))
        let controller = try await rendererController(samples: [sample], date: date)
        let root = { (phase: ScenePhase) in
            ImportPreviewView(controller: controller, retry: {})
                .environment(\.scenePhase, phase)
        }
        let host = UIHostingController(rootView: root(.active))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        for phase in [ScenePhase.inactive, .background, .active] {
            host.rootView = root(phase)
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            XCTAssertEqual(findScrollView(in: host.view) != nil, phase == .active,
                           "The list containing pump records must leave the hierarchy before snapshotting")
            guard case .ready(let plan) = controller.state else {
                return XCTFail("Loaded records disappeared after scene phase \(phase)")
            }
            XCTAssertEqual(plan.samples.map(\.original.externalId), ["retained"])
            XCTAssertEqual(plan.concentration, .u200)
        }
    }

    func testInspectionOrdersNewestFirstWithoutChangingImportOrder() async throws {
        let date = Date(timeIntervalSince1970: 1_791_158_400)
        let samples = [("old", 0.0), ("latest", 120.0), ("middle-a", 60.0), ("middle-z", 60.0)].map { id, offset in
            SampleDTO(externalId: id, type: "insulin.bolus", value: 1, unit: "IU", startAt: date.addingTimeInterval(offset), endAt: date.addingTimeInterval(offset), metadata: [:], source: .init(deviceId: "Test pump", eventIds: [id]))
        }
        let controller = try await rendererController(samples: samples, date: date)
        XCTAssertEqual(controller.recordsNewestFirst.map(\.original.externalId), ["latest", "middle-z", "middle-a", "old"])
        guard case .ready(let plan) = controller.state else { return XCTFail("Expected records") }
        XCTAssertEqual(plan.samples.map(\.original.externalId), ["old", "middle-a", "middle-z", "latest"])
        XCTAssertEqual(controller.recordsNewestFirst.first?.original.value, 1)
        XCTAssertEqual(controller.recordsNewestFirst.first?.convertedValue, 2)
    }

    func testFailedRefreshRetainsSnapshotConcentrationAndTimestamp() async throws {
        let date = Date(timeIntervalSince1970: 1_791_158_400)
        let controller = try await rendererController(samples: [], date: date)
        guard case .ready(let original) = controller.state else { return XCTFail("Expected initial snapshot") }
        let loadedAt = try XCTUnwrap(controller.loadedAt)
        await source?.setResult(.failure(.unavailable))
        await controller.load(request: request(), context: original.context, concentration: .u500)
        guard case .ready(let retained) = controller.state else { return XCTFail("Refresh failure must keep the loaded snapshot") }
        XCTAssertEqual(retained, original)
        XCTAssertEqual(retained.concentration, .u200)
        XCTAssertEqual(controller.loadedAt, loadedAt)
        XCTAssertNotNil(controller.refreshError)
        XCTAssertFalse(controller.isRefreshing)
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
        try await capture(try await rendererController(samples: samples, date: date), name: "test-target-ready-AX5-light", size: CGSize(width: 402, height: 874), text: .accessibility5, color: .light)
        ready.fail("Your Tandem account changed. Load the records again.")
        try await capture(ready, name: "test-target-failure-light", size: CGSize(width: 402, height: 874), text: .large, color: .light, requiresReady: false)
        let context = snapshot()
        let dataSource = DirectImportTestSource(.failure(.unavailable), held: true)
        let loading = ImportPreviewController(dataSource: dataSource, currentContext: { context })
        let loadingTask = Task { await loading.load(request: request(), context: context, concentration: .u100) }
        await Task.yield()
        guard case .loading = loading.state else { return XCTFail("Expected loading fixture") }
        try await capture(loading, name: "test-target-loading-light", size: CGSize(width: 402, height: 874), text: .large, color: .light, requiresReady: false)
        loading.cancel()
        await dataSource.release()
        await loadingTask.value
    }

    private func rendererController(samples: [SampleDTO], date: Date) async throws -> ImportPreviewController {
        let context = snapshot()
        let source = DirectImportTestSource(.success(.init(samples: samples, effectiveMinDate: date, effectiveMaxDate: date.addingTimeInterval(7200), dataSourceMode: .tandemSource)))
        self.source = source
        let controller = ImportPreviewController(dataSource: source, currentContext: { context })
        await controller.load(request: request(), context: context, concentration: .u200)
        guard case .ready = controller.state else { throw DirectTandemError.invalidResponse }
        return controller
    }

    private func capture(_ controller: ImportPreviewController, name: String, size: CGSize, text: DynamicTypeSize, color: ColorScheme, scrollOffset: CGFloat = 0, requiresReady: Bool = true) async throws {
        let host = UIHostingController(rootView: NavigationStack {
            ImportPreviewView(controller: controller, retry: {})
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
        if requiresReady {
            guard case .ready = controller.state else { return XCTFail("Renderer lost ready data before capture") }
        }
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

    private func snapshot() -> ImportSessionSnapshot {
        .init(accountId: UUID(), credentialRevision: 0)
    }
    private func request() -> TandemSyncRequest {
        .init(tandem: .init(username: "fixture", password: "fixture", region: "us"), minDate: nil, maxDate: nil, timeZoneIdentifier: "UTC")
    }

}
