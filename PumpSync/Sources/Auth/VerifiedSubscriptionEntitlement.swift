import Foundation
import StoreKit

enum HostedSubscriptionEnvironment: String, Codable, Sendable {
  case sandbox
  case production

  init?(storeKitEnvironment: AppStore.Environment) {
    switch storeKitEnvironment {
    case .sandbox: self = .sandbox
    case .production: self = .production
    default: return nil
    }
  }
}

/// Only a locally verified StoreKit transaction may select a hosted backend.
/// Server-side signature, identity, environment, and entitlement checks remain required.
struct VerifiedSubscriptionEntitlement: Sendable {
  let signedTransactionInfo: String
  let environment: HostedSubscriptionEnvironment

  private init(signedTransactionInfo: String, environment: HostedSubscriptionEnvironment) {
    self.signedTransactionInfo = signedTransactionInfo
    self.environment = environment
  }

  static func verified(_ result: VerificationResult<Transaction>) throws -> Self {
    guard case .verified(let transaction) = result else {
      throw StoreKitSubscriptionError.unverifiedTransaction
    }
    guard transaction.productID == AppConstants.subscriptionProductId,
          transaction.isActiveSubscriptionEntitlement else {
      throw StoreKitSubscriptionError.inactiveSubscriptionTransaction
    }
    guard let environment = HostedSubscriptionEnvironment(storeKitEnvironment: transaction.environment) else {
      throw StoreKitSubscriptionError.unverifiedTransaction
    }
    return Self(signedTransactionInfo: result.jwsRepresentation, environment: environment)
  }

#if DEBUG
  static func fixture(_ jws: String, environment: HostedSubscriptionEnvironment = .sandbox) -> Self {
    Self(signedTransactionInfo: jws, environment: environment)
  }
#endif
}
