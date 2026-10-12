import Foundation
import Observation

enum SyncAttemptStage: String, Codable { case recovering, validating, downloading, updatingHealth, terminal }
enum SyncAttemptOutcome: String, Codable { case completed, skipped, blocked, deferred, canceled, contextReplaced, failed, interrupted }
enum SyncAttemptReason: Codable, Equatable {
  case completed, fresh, credentials, healthPermission, unverifiedSource, executionLeaseExpired
  case canceled, contextReplaced, requestFailed, proofUnavailable, processInterrupted
  case recovery(SessionRecoveryReason)

  var description: String {
    switch self {
    case .recovery(let reason): return reason.rawValue
    case .completed: return "completed"
    case .fresh: return "fresh"
    case .credentials: return "credentials"
    case .healthPermission: return "healthPermission"
    case .unverifiedSource: return "unverifiedSource"
    case .executionLeaseExpired: return "executionLeaseExpired"
    case .canceled: return "canceled"
    case .contextReplaced: return "contextReplaced"
    case .requestFailed: return "requestFailed"
    case .proofUnavailable: return "proofUnavailable"
    case .processInterrupted: return "processInterrupted"
    }
  }
}

/// Only operation-local IDs and allowlisted categories enter this record.
/// Account/connection IDs, request payloads and error descriptions have no field.
struct SyncAttempt: Codable, Equatable {
  let operationID: UUID
  let trigger: SyncTriggerReason
  let startedAt: Date
  var stage: SyncAttemptStage
  var outcome: SyncAttemptOutcome?
  var reason: SyncAttemptReason?
  var durationSeconds: TimeInterval?
  var backendCorrelationID: String?
}

@MainActor
@Observable
final class SyncAttemptStore {
  private struct State: Codable { var history: [SyncAttempt] = []; var active: SyncAttempt? }
  private static let key = "sync-attempt-history-v1"
  private let defaults: UserDefaults
  private let diagnostics: DiagnosticsLogStore?
  private(set) var history: [SyncAttempt]
  private(set) var active: SyncAttempt?

  init(defaults: UserDefaults = .standard, diagnostics: DiagnosticsLogStore? = nil, now: Date = Date()) {
    self.defaults = defaults
    self.diagnostics = diagnostics
    let state = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    history = Array(state.history.prefix(20))
    active = state.active
    if let interrupted = active {
      finish(operationID: interrupted.operationID, outcome: .interrupted, reason: .processInterrupted, at: now)
    }
  }

  func begin(operationID: UUID, trigger: SyncTriggerReason, at: Date = Date()) {
    guard active == nil else { return }
    active = SyncAttempt(operationID: operationID, trigger: trigger, startedAt: at, stage: .recovering)
    persistAndLog()
  }

  func advance(operationID: UUID, stage: SyncAttemptStage) {
    guard active?.operationID == operationID else { return }
    active?.stage = stage
    persistAndLog()
  }

  func correlate(operationID: UUID, value: String?) {
    guard active?.operationID == operationID, let value,
          value.range(of: #"^(?:[0-9A-Z]{13}:[0-9A-F]{8}|[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$"#, options: .regularExpression) != nil else { return }
    active?.backendCorrelationID = value.lowercased()
    persist()
  }

  func finish(operationID: UUID, outcome: SyncAttemptOutcome, reason: SyncAttemptReason, at: Date = Date()) {
    guard var attempt = active, attempt.operationID == operationID else { return }
    attempt.outcome = outcome
    attempt.reason = reason
    attempt.durationSeconds = max(0, at.timeIntervalSince(attempt.startedAt))
    history.insert(attempt, at: 0)
    history = Array(history.prefix(20))
    active = nil
    persist()
    log(attempt)
  }

  func finish(operationID: UUID, result: SyncRunOutcome) {
    switch result {
    case .completed: finish(operationID: operationID, outcome: .completed, reason: .completed)
    case .skippedFresh: finish(operationID: operationID, outcome: .skipped, reason: .fresh)
    case .skippedPreviewActive: finish(operationID: operationID, outcome: .skipped, reason: .unverifiedSource)
    case .blocked(let reason):
      switch reason {
      case .session(let reason): finish(operationID: operationID, outcome: .blocked, reason: .recovery(reason))
      case .credentials: finish(operationID: operationID, outcome: .blocked, reason: .credentials)
      case .healthPermission: finish(operationID: operationID, outcome: .blocked, reason: .healthPermission)
      case .unverifiedSource: finish(operationID: operationID, outcome: .blocked, reason: .unverifiedSource)
      }
    case .deferred(let reason):
      switch reason {
      case .executionLeaseExpired: finish(operationID: operationID, outcome: .deferred, reason: .executionLeaseExpired)
      case .recovery(let reason): finish(operationID: operationID, outcome: .deferred, reason: .recovery(reason))
      }
    case .canceled: finish(operationID: operationID, outcome: .canceled, reason: .canceled)
    case .contextReplaced: finish(operationID: operationID, outcome: .contextReplaced, reason: .contextReplaced)
    case .failed: finish(operationID: operationID, outcome: .failed, reason: .requestFailed)
    }
  }

  private func persistAndLog() { persist(); if let active { log(active) } }
  private func persist() {
    if let data = try? JSONEncoder().encode(State(history: history, active: active)) { defaults.set(data, forKey: Self.key) }
  }
  private func log(_ attempt: SyncAttempt) {
    diagnostics?.record(source: .sync, title: "Owned sync attempt", message: Self.description(attempt))
  }
  nonisolated static func description(_ attempt: SyncAttempt) -> String {
    "operation=\(attempt.operationID) trigger=\(attempt.trigger.rawValue) stage=\(attempt.stage.rawValue) outcome=\(attempt.outcome?.rawValue ?? "active") reason=\(attempt.reason?.description ?? "inProgress") durationSeconds=\(attempt.durationSeconds.map { String(Int($0)) } ?? "pending") correlation=\(attempt.backendCorrelationID ?? "unavailable")"
  }
}
