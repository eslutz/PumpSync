import Foundation
import StoreKit

enum SubscriptionRestoreOutcome: Equatable {
    case restored
    case cancelled
    case noActiveSubscription
    case appStoreUnavailable
    case backendVerificationFailed

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case StoreKitError.userCancelled = error { return true }
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == SKErrorDomain && error.code == SKError.paymentCancelled.rawValue)
    }
}
