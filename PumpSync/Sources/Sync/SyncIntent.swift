import Foundation
import Synchronization

/// A scene-owned lease or the finite budget granted by BGTaskScheduler.
/// Revocation is thread-safe so a system expiration handler can fence work
/// before its cancellation reaches the main actor.
final class SyncExecutionLease: Sendable {
  enum Kind: Sendable { case foreground, background }
  let kind: Kind
  private let deadline: Date?
  private let revoked = Mutex(false)

  init(kind: Kind, deadline: Date? = nil) {
    self.kind = kind
    self.deadline = deadline
  }

  var isValid: Bool {
    !revoked.withLock { $0 } && (deadline.map { Date() < $0 } ?? (kind == .foreground))
  }

  func revoke() { revoked.withLock { $0 = true } }
}

/// Immutable guards and trigger belong to the execution, including its single
/// replacement attempt. A replacement always captures a new import snapshot.
struct SyncIntent {
  let operationID: UUID
  let trigger: SyncTriggerReason
  let configuration: ImportConfigurationSnapshot
  let credentialRevision: Int
  let concentration: InsulinConcentration
  let initialContext: ImportSessionSnapshot?
  let lease: SyncExecutionLease
  let recoveryPolicy: SessionRecoveryPolicy
  let reevaluatesFreshnessAfterRecovery: Bool
}

enum SyncBlockReason: Equatable {
  case session(SessionRecoveryReason)
  case credentials
  case healthPermission
  case unverifiedSource
}

enum SyncDeferralReason: Equatable {
  case executionLeaseExpired
  case recovery(SessionRecoveryReason)
}

enum SyncRunOutcome: Equatable {
  case completed
  case skippedFresh
  case skippedPreviewActive
  case blocked(SyncBlockReason)
  case deferred(SyncDeferralReason)
  case canceled
  case contextReplaced
  case failed

  var succeeded: Bool {
    self == .completed || self == .skippedFresh
  }
}
