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

struct SyncIntent {
  let operationID: UUID
  let trigger: SyncTriggerReason
  let context: ImportSessionSnapshot?
  let concentration: InsulinConcentration
  let initialRange: InitialImportRange
}

enum SyncBlockReason: Equatable {
  case credentials
  case healthPermission
  case unverifiedSource
}

enum SyncDeferralReason: Equatable {
  case executionLeaseExpired
  case rateLimited
}

enum SyncRunOutcome: Equatable {
  case completed
  case skippedFresh
  case blocked(SyncBlockReason)
  case deferred(SyncDeferralReason)
  case canceled
  case contextReplaced
  case failed

  var succeeded: Bool {
    self == .completed || self == .skippedFresh
  }
}
