import Foundation
import Observation
import StoreKit

enum SubscriptionAccessStatus: Equatable {
    case unknown, active, inactive, unavailable
}

/// A delivered update carries its acknowledgement separately from an entitlement
/// read. Looking up access must never finish a transaction as a side effect.
enum SubscriptionUpdate {
    case active(VerifiedSubscriptionEntitlement, summary: String, finish: @MainActor () async -> Void)
    case inactive(HostedSubscriptionEnvironment?, summary: String, finish: @MainActor () async -> Void)
    case unverified
}

@MainActor
protocol SubscriptionAccessProviding: AnyObject {
    var accessStatus: SubscriptionAccessStatus { get }
    func currentEntitlement() async throws -> VerifiedSubscriptionEntitlement
    func restoreEntitlement() async throws -> VerifiedSubscriptionEntitlement
    func startObserving(_ receive: @escaping @MainActor (SubscriptionUpdate) async -> Void)
}

@MainActor
@Observable
final class StoreKitSubscriptionService: SubscriptionAccessProviding {
    typealias UpdateObserver = @MainActor (@escaping @MainActor (SubscriptionUpdate) async -> Void) -> Task<Void, Never>

    private(set) var accessStatus: SubscriptionAccessStatus = .unknown
    private let loadEntitlement: @MainActor () async throws -> VerifiedSubscriptionEntitlement
    private let synchronize: @MainActor () async throws -> Void
    private let observeUpdates: UpdateObserver
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(
        loadEntitlement: @escaping @MainActor () async throws -> VerifiedSubscriptionEntitlement = StoreKitSubscriptionService.loadCurrentEntitlement,
        synchronize: @escaping @MainActor () async throws -> Void = { try await AppStore.sync() },
        observeUpdates: @escaping UpdateObserver = StoreKitSubscriptionService.observeStoreKitUpdates
    ) {
        self.loadEntitlement = loadEntitlement
        self.synchronize = synchronize
        self.observeUpdates = observeUpdates
    }

    deinit { updatesTask?.cancel() }

    func currentEntitlement() async throws -> VerifiedSubscriptionEntitlement {
        do {
            let entitlement = try await loadEntitlement()
            accessStatus = .active
            return entitlement
        } catch StoreKitSubscriptionError.noActiveSubscription {
            accessStatus = .inactive
            throw StoreKitSubscriptionError.noActiveSubscription
        } catch {
            accessStatus = .unavailable
            throw error
        }
    }

    /// Only an explicit restore action may call this method; normal access reads
    /// use StoreKit's automatically maintained current entitlements.
    func restoreEntitlement() async throws -> VerifiedSubscriptionEntitlement {
        try await synchronize()
        try Task.checkCancellation()
        return try await currentEntitlement()
    }

    func startObserving(_ receive: @escaping @MainActor (SubscriptionUpdate) async -> Void) {
        guard updatesTask == nil else { return }
        updatesTask = observeUpdates { [weak self] update in
            // Refresh the whole entitlement set rather than interpreting a historical
            // expired update as the current subscription state.
            if let self { _ = try? await self.currentEntitlement() }
            await receive(update)
        }
    }

    private static func loadCurrentEntitlement() async throws -> VerifiedSubscriptionEntitlement {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                throw StoreKitSubscriptionError.unverifiedTransaction
            }
            guard transaction.productID == AppConstants.subscriptionProductId,
                        transaction.isActiveSubscriptionEntitlement else { continue }
            return try VerifiedSubscriptionEntitlement.verified(result)
        }
        throw StoreKitSubscriptionError.noActiveSubscription
    }

    private static func observeStoreKitUpdates(
        _ receive: @escaping @MainActor (SubscriptionUpdate) async -> Void
    ) -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result else {
                    await receive(.unverified)
                    continue
                }
                // Other products belong to their own delivery handler, not this service.
                guard transaction.productID == AppConstants.subscriptionProductId else { continue }
                if transaction.isActiveSubscriptionEntitlement {
                    guard let entitlement = try? VerifiedSubscriptionEntitlement.verified(result) else {
                        await receive(.unverified)
                        continue
                    }
                    await receive(.active(entitlement, summary: transaction.diagnosticSummary(active: true), finish: { await transaction.finish() }))
                } else {
                    await receive(.inactive(HostedSubscriptionEnvironment(storeKitEnvironment: transaction.environment),
                        summary: transaction.diagnosticSummary(active: false), finish: { await transaction.finish() }))
                }
            }
        }
    }
}
