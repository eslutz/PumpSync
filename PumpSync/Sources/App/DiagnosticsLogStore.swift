import Foundation
import Observation

enum DiagnosticSource: String, Codable {
  case auth = "Sign in"
  case sync = "Sync"
  case credential = "Pump Credentials"
  case health = "Apple Health"
}

enum DiagnosticSeverity: String, Codable {
  case info = "Info"
  case warning = "Warning"
  case error = "Error"
}

enum DiagnosticsRedactor {
  static func redacted(_ message: String) -> String {
    var result = message
    let replacements: [(String, String)] = [
      (#"(?i)(password|passwd|accessToken|refreshToken|authorization|signedTransactionInfo|attestationObject|assertion|challengeToken|clientSecret)[\"\']?\s*[:=]\s*"(?:\\.|[^"\\])*""#, "$1=[redacted-secret]"),
      (#"(?i)(password|passwd|accessToken|refreshToken|authorization|signedTransactionInfo|attestationObject|assertion|challengeToken|clientSecret)[\"\']?\s*[:=]\s*'(?:\\.|[^'\\])*'"#, "$1=[redacted-secret]"),
      (#"(?i)\b(authorization)\s*[:=]\s*(?:Bearer|Basic)\s+[^\s,;]+"#, "$1=[redacted-secret]"),
      (#"(?i)(password|passwd|accessToken|refreshToken|authorization|signedTransactionInfo|attestationObject|assertion|challengeToken|clientSecret)\s*[\"\']?\s*[:=]\s*[\"\']?[^\s,;\"\'}]+"#, "$1=[redacted-secret]"),
      (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "[redacted email]"),
      (#"Bearer\s+[A-Za-z0-9._\-]+"#, "Bearer [redacted token]"),
      (#"\beyJ[A-Za-z0-9._\-]{20,}\b"#, "[redacted token]"),
      (#"\bps(?:rt|c)1\.[A-Za-z0-9_\-\.]{20,}\b"#, "[redacted renewable credential]"),
      (#"\b[A-Za-z0-9_\-]{32,}\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}\b"#, "[redacted token]")
    ]

    for (pattern, replacement) in replacements {
      result = result.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: [.regularExpression, .caseInsensitive]
      )
    }

    return result
  }
}

struct DiagnosticEntry: Identifiable, Equatable, Codable {
  let id: UUID
  let timestamp: Date
  let source: DiagnosticSource
  let severity: DiagnosticSeverity
  let title: String
  let message: String?
  var syncAttempt: SyncAttempt? = nil
  var importPreview: ImportPreviewDiagnostic? = nil

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    source: DiagnosticSource,
    severity: DiagnosticSeverity,
    title: String,
    message: String?,
    syncAttempt: SyncAttempt? = nil,
    importPreview: ImportPreviewDiagnostic? = nil
  ) {
    self.syncAttempt = syncAttempt
    self.importPreview = importPreview
    self.id = id
    self.timestamp = timestamp
    self.source = source
    self.severity = severity
    self.title = DiagnosticsRedactor.redacted(title)
    self.message = message.map(DiagnosticsRedactor.redacted)
  }

  private enum CodingKeys: String, CodingKey {
    case id, timestamp, source, severity, title, message, syncAttempt, importPreview
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try values.decode(UUID.self, forKey: .id),
      timestamp: try values.decode(Date.self, forKey: .timestamp),
      source: try values.decode(DiagnosticSource.self, forKey: .source),
      severity: try values.decode(DiagnosticSeverity.self, forKey: .severity),
      title: try values.decode(String.self, forKey: .title),
      message: try values.decodeIfPresent(String.self, forKey: .message),
      syncAttempt: try values.decodeIfPresent(SyncAttempt.self, forKey: .syncAttempt),
      // Older or future optional metadata must not discard the retained log.
      importPreview: try? values.decodeIfPresent(ImportPreviewDiagnostic.self, forKey: .importPreview)
    )
  }
}

/// Only the state, known source and record count are retained, never pump records.
struct ImportPreviewDiagnostic: Codable, Equatable {
  enum Status: String, Codable { case idle, loading, ready, failed }
  let status: Status
  let source: DataSourceMode?
  let recordCount: Int?

  init(status: Status, source: DataSourceMode? = nil, recordCount: Int? = nil) {
    self.status = status
    self.source = status == .ready ? source : nil
    self.recordCount = status == .ready ? recordCount.flatMap { $0 >= 0 ? $0 : nil } : nil
  }

  private enum CodingKeys: String, CodingKey { case status, source, recordCount }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(status: try values.decode(Status.self, forKey: .status),
      source: try values.decodeIfPresent(DataSourceMode.self, forKey: .source),
      recordCount: try values.decodeIfPresent(Int.self, forKey: .recordCount))
  }
}

@MainActor
@Observable
final class DiagnosticsLogStore {
  private static let maxEntries = 200
  private static let defaultsKey = "diagnostics-log"

  private let defaults: UserDefaults
  private(set) var entries: [DiagnosticEntry]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.entries = Self.load(defaults: defaults)
  }

  func record(
    source: DiagnosticSource,
    severity: DiagnosticSeverity = .info,
    title: String,
    message: String? = nil,
    syncAttempt: SyncAttempt? = nil,
    importPreview: ImportPreviewDiagnostic? = nil
  ) {
    // message is redacted here, before the entry is ever constructed, so the
    // persisted copy below carries the exact same redaction as what's held
    // in memory — there's no separate persistence-time redaction step to
    // keep in sync.
    let entry = DiagnosticEntry(
      source: source,
      severity: severity,
      title: title,
      message: message.map(Self.redacted),
      syncAttempt: syncAttempt,
      importPreview: importPreview
    )
    entries.insert(entry, at: 0)

    if entries.count > Self.maxEntries {
      entries.removeLast(entries.count - Self.maxEntries)
    }

    save()
  }

  func record(error: Error, source: DiagnosticSource, title: String) {
    record(source: source, severity: .error, title: title, message: error.localizedDescription)
  }

  func clear() {
    entries.removeAll()
    defaults.removeObject(forKey: Self.defaultsKey)
  }

  nonisolated static func redacted(_ message: String) -> String {
    DiagnosticsRedactor.redacted(message)
  }

  private func save() {
    if let data = try? JSONEncoder().encode(entries) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }

  private static func load(defaults: UserDefaults) -> [DiagnosticEntry] {
    guard
      let data = defaults.data(forKey: defaultsKey),
      let entries = try? JSONDecoder().decode([DiagnosticEntry].self, from: data)
    else {
      return []
    }

    let sanitized = entries.prefix(maxEntries).map {
      DiagnosticEntry(id: $0.id, timestamp: $0.timestamp, source: $0.source, severity: $0.severity, title: $0.title, message: $0.message, syncAttempt: $0.syncAttempt, importPreview: $0.importPreview)
    }
    if let data = try? JSONEncoder().encode(sanitized) { defaults.set(data, forKey: defaultsKey) }
    return sanitized
  }
}
