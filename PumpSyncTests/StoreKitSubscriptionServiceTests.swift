import StoreKit
import XCTest
@testable import PumpSync

@MainActor
final class StoreKitSubscriptionServiceTests: XCTestCase {
    func testSilentReadDoesNotSynchronizeAndRestoreSynchronizesExactlyOnce() async throws {
        var reads = 0
        var syncs = 0
        let service = StoreKitSubscriptionService(
            loadEntitlement: { reads += 1; return .fixture("verified") },
            synchronize: { syncs += 1 },
            observeUpdates: { _ in Task {} }
        )

        XCTAssertEqual(service.accessStatus, .unknown)
        _ = try await service.currentEntitlement()
        XCTAssertEqual(syncs, 0)
        XCTAssertEqual(service.accessStatus, .active)
        _ = try await service.restoreEntitlement()
        XCTAssertEqual(syncs, 1)
        XCTAssertEqual(reads, 2)
    }

    func testFailedOrCancelledRestoreDoesNotUseCachedEntitlementAsSuccess() async {
        for failure: Error in [URLError(.notConnectedToInternet), StoreKitError.userCancelled, CancellationError()] {
            var reads = 0
            let service = StoreKitSubscriptionService(
                loadEntitlement: { reads += 1; return .fixture("cached") },
                synchronize: { throw failure },
                observeUpdates: { _ in Task {} }
            )
            do {
                _ = try await service.restoreEntitlement()
                XCTFail("The synchronization error must reach the explicit restore caller")
            } catch {
                XCTAssertEqual(SubscriptionRestoreOutcome.isCancellation(error), SubscriptionRestoreOutcome.isCancellation(failure))
            }
            XCTAssertEqual(reads, 0)
        }
    }

    func testMissingAndUnverifiableEntitlementsHaveDifferentStatus() async {
        let missing = StoreKitSubscriptionService(
            loadEntitlement: { throw StoreKitSubscriptionError.noActiveSubscription },
            synchronize: {}, observeUpdates: { _ in Task {} }
        )
        let unverifiable = StoreKitSubscriptionService(
            loadEntitlement: { throw StoreKitSubscriptionError.unverifiedTransaction },
            synchronize: {}, observeUpdates: { _ in Task {} }
        )
        _ = try? await missing.currentEntitlement()
        XCTAssertEqual(missing.accessStatus, .inactive)
        _ = try? await unverifiable.currentEntitlement()
        XCTAssertEqual(unverifiable.accessStatus, .unavailable)
    }

    func testOneListenerAndDeliveryAcknowledgementBelongsToConsumer() async throws {
        var listeners = 0
        var finishCount = 0
        var receive: (@MainActor (SubscriptionUpdate) async -> Void)?
        var pendingFinish: (@MainActor () async -> Void)?
        let service = StoreKitSubscriptionService(
            loadEntitlement: { .fixture("active") }, synchronize: {},
            observeUpdates: { handler in
                listeners += 1
                receive = handler
                return Task {}
            }
        )
        XCTAssertEqual(listeners, 0, "Creating a candidate service must not create a listener")
        service.startObserving { update in
            if case .active(_, _, let finish) = update { pendingFinish = finish }
        }
        service.startObserving { _ in XCTFail("A second call must not replace the lifetime listener") }
        XCTAssertEqual(listeners, 1)

        await receive?(.active(.fixture("active"), summary: "active=true", finish: { finishCount += 1 }))
        _ = try await service.currentEntitlement()
        _ = try await service.restoreEntitlement()
        XCTAssertEqual(finishCount, 0, "Reading or restoring access cannot acknowledge delivery")
        await pendingFinish?()
        XCTAssertEqual(finishCount, 1)
    }

    func testDestroyingServiceCancelsItsListener() async {
        var listenerStarted = false
        var listenerCancelled = false
        var service: StoreKitSubscriptionService? = StoreKitSubscriptionService(
            loadEntitlement: { .fixture("active") }, synchronize: {},
            observeUpdates: { _ in
                Task {
                    listenerStarted = true
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { listenerCancelled = true }
                }
            }
        )
        service?.startObserving { _ in }
        await waitUntil { listenerStarted }
        service = nil
        await waitUntil { listenerCancelled }
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !predicate(), Date() < deadline { await Task.yield() }
        XCTAssertTrue(predicate())
    }
}
