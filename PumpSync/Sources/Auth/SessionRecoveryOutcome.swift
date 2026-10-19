import Foundation

enum SessionRecoveryTransition: Equatable {
  case cached
  case refreshed
  case reenrolled
}

/// Stable, support-safe reasons; raw network/storage errors never escape here.
enum SessionRecoveryReason: String, Codable, Equatable {
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
  case deviceProofRejected
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
  var backendCorrelationID: String?
  private var requestLinks: [SyncRequestLink] = []
  private var droppedRequestLinkCount = 0

  func recordRequestLink(_ link: SyncRequestLink) {
    if let index = requestLinks.firstIndex(where: { $0.requestID == link.requestID }) {
      requestLinks[index] = link
    } else if requestLinks.count < 32 {
      requestLinks.append(link)
    } else if !link.responseReceived {
      droppedRequestLinkCount += 1
    }
  }

  func replayRequestLinks() {
    guard let context = SyncDiagnosticContext.current else { return }
    for link in requestLinks { context.record(link) }
    context.recordDropped(droppedRequestLinkCount)
  }
}

typealias SessionRecoveryPolicyProvider = @MainActor @Sendable () -> SessionRecoveryPolicy

enum SessionRecoveryContext {
  @TaskLocal static var current: SessionRecoveryAttempt?
  // Recovery may suspend while its scene owner ends. Read the surviving
  // owners again at each policy decision instead of retaining permission to UI.
  @TaskLocal static var policyProvider: SessionRecoveryPolicyProvider?
}
