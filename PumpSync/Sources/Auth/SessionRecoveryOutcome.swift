import Foundation

enum SessionRecoveryTransition: Equatable {
  case cached
  case refreshed
  case reenrolled
}

/// Stable, support-safe reasons; raw network/storage errors never escape here.
enum SessionRecoveryReason: Equatable {
  case uncertainSubmission
  case commitPending
  case invalidationIncomplete
  case storageUnavailable
  case networkUnavailable
  case appAttestUnavailable
  case appAttestTimedOut
  case proofOperationInProgress
  case missingEntitlement
  case interactiveRecoveryRequired
  case configurationInvalid
  case connectionReplaced
  case authenticationRejected
  case backendRejected
  case invalidDeviceKey
  case unverifiedSource
  case unavailable
}

enum SessionRecoveryOutcome: Equatable {
  case ready(AuthenticatedConnection, transition: SessionRecoveryTransition)
  case deferred(SessionRecoveryReason)
  case requiresUserAction(SessionRecoveryReason)
  case rejected(SessionRecoveryReason)
  case canceled
}

@MainActor
final class SessionRecoveryAttempt {
  var failure: SessionRecoveryReason?
}

enum SessionRecoveryContext {
  @TaskLocal static var current: SessionRecoveryAttempt?
}
