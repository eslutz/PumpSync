import Foundation

enum DiagnosticPresentation {
  static func title(for entry: DiagnosticEntry) -> String {
    guard let attempt = entry.syncAttempt else { return DiagnosticsRedactor.redacted(entry.title) }
    let trigger: String = switch attempt.trigger {
    case .manual: "Manual"
    case .appOpen: "App-open"
    case .background: "Background"
    }
    let outcome: String = switch attempt.outcome {
    case .completed: "completed"
    case .failed: "failed"
    case .blocked: "needs attention"
    case .deferred: "deferred"
    case .skipped: "already up to date"
    case .canceled: "canceled"
    case .contextReplaced: "stopped after settings changed"
    case .interrupted: "interrupted"
    case nil: attempt.stage.rawValue
    }
    return "\(trigger) sync \(outcome)"
  }

  static func summary(for entry: DiagnosticEntry) -> String? {
    guard let attempt = entry.syncAttempt else {
      return entry.message.map(DiagnosticsRedactor.redacted)
    }
    guard let returned = attempt.returnedCount else { return reason(for: attempt) ?? "Counts not recorded for this stage." }
    var parts = [String(localized: "\(returned) records received"), attempt.importedCount.map { String(localized: "\($0) samples saved") } ?? String(localized: "Saved count unavailable")]
    if let skipped = attempt.permissionSkippedCount, skipped > 0 { parts.append("\(skipped) awaiting Health access") }
    return parts.joined(separator: " · ")
  }

  static func reason(for attempt: SyncAttempt) -> String? {
    switch attempt.reason {
    case .completed, .none: return nil
    case .fresh: return String(localized: "The last successful sync is recent; no download was needed.")
    case .credentials: return String(localized: "Save and validate your Tandem account in Settings.")
    case .healthPermission: return String(localized: "Allow PumpSync to write to Apple Health, then sync again.")
    case .unverifiedSource: return String(localized: "The source could not be verified. No new samples were submitted.")
    case .executionLeaseExpired: return String(localized: "iOS ended the available background time. Open PumpSync to try again.")
    case .canceled: return String(localized: "The sync was canceled.")
    case .contextReplaced: return String(localized: "The account or connection changed during this sync.")
    case .requestFailed: return String(localized: "The request failed. Open the technical details for the retained record.")
    case .proofUnavailable: return String(localized: "Device verification was unavailable. Open PumpSync to reconnect.")
    case .processInterrupted: return String(localized: "The app stopped before it recorded an outcome. The actual end time is unknown.")
    case .recovery(let reason):
      switch reason {
      case .networkUnavailable: return String(localized: "The network was unavailable. Try again when connected.")
      case .missingEntitlement: return String(localized: "No active PumpSync subscription was found.")
      case .storageUnavailable: return String(localized: "Secure storage was unavailable. Unlock the device and open PumpSync.")
      case .configurationInvalid: return String(localized: "Review the connection configuration in Settings.")
      case .connectionReplaced: return String(localized: "The connection changed while access was being restored.")
      case .interactiveRecoveryRequired: return String(localized: "Open PumpSync to finish reconnecting.")
      case .uncertainSubmission, .commitPending, .invalidationIncomplete:
        return String(localized: "A previous connection change still needs to be reconciled.")
      case .appAttestUnavailable, .appAttestTimedOut, .proofOperationInProgress, .deviceProofRejected, .invalidDeviceKey:
        return String(localized: "Device verification could not complete. Open PumpSync to reconnect.")
      case .authenticationRejected, .backendRejected:
        return String(localized: "The service did not accept this connection. Review Settings.")
      case .unverifiedSource: return String(localized: "The service could not verify the pump data source.")
      case .unavailable: return String(localized: "The secure connection could not be restored.")
      }
    }
  }

  static func exactTime(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }

  static func export(_ entry: DiagnosticEntry) -> String {
    DiagnosticsRedactor.redacted([
      exactTime(entry.timestamp), entry.source.rawValue, entry.severity.rawValue,
      title(for: entry),
      entry.syncAttempt.map(SyncAttemptStore.description) ?? entry.message ?? ""
    ].filter { !$0.isEmpty }.joined(separator: " | "))
  }

  static func export(_ entry: NativeDiagnosticEntry) -> String {
    let report = entry.report.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.json.utf8))).map { NativeDiagnosticReport.make(from: $0) } }
    return DiagnosticsRedactor.redacted([
      exactTime(entry.timestamp), entry.kind.rawValue, entry.title,
      "App \(entry.appVersion) (\(entry.buildNumber))", entry.summary,
      report?.json ?? "Legacy summary only; original payload was not retained."
    ].joined(separator: "\n"))
  }
}

struct SyncHistoryPresentation {
  let lastAttempt: Date?
  let lastSuccess: Date?
  let returned: Int?
  let imported: Int?
  let permissionSkipped: Int?
  let resetDescription: String?

  var countsSummary: String? {
    guard lastSuccess != nil else { return nil }
    var parts = [returned.map { String(localized: "\($0) records received") } ?? String(localized: "Received count unavailable"),
                 imported.map { String(localized: "\($0) samples saved") } ?? String(localized: "Saved count unavailable")]
    if let permissionSkipped, permissionSkipped > 0 { parts.append("\(permissionSkipped) awaiting Health access") }
    return parts.joined(separator: " · ")
  }

  init(metadata: SyncMetadata, attempts: [SyncAttempt]) {
    lastAttempt = attempts.first { $0.historyScopeID == metadata.historyScopeID }?.startedAt ?? metadata.lastAttemptAt
    lastSuccess = metadata.lastSuccessfulSyncAt
    returned = lastSuccess == nil ? nil : metadata.lastSampleCount
    imported = lastSuccess == nil ? nil : metadata.lastImportedCount
    permissionSkipped = metadata.lastPermissionSkippedCount
    resetDescription = metadata.cursorResetReason.map {
      switch $0 {
      case .legacyUnbound: "Earlier history could not be bound to this account and server."
      case .accountChanged: "History restarted when the Tandem account changed."
      case .backendChanged: "History restarted when the server changed."
      case .credentialsDeleted: "History restarted when saved credentials were removed."
      }
    }
  }
}

/// Retain supported numeric fields and validated metadata, never arbitrary strings
/// or full crash payloads. JSON is lossless for these allowlisted fields only.
