import Foundation
import Observation

enum DiagnosticSource: String, CaseIterable, Identifiable, Codable {
  case auth = "Sign in"
  case sync = "Sync"
  case credential = "Pump Credentials"
  case health = "Apple Health"
  case backgroundSync = "Background Sync"
  case api = "API"

  var id: String { rawValue }
}

enum DiagnosticSeverity: String, Codable {
  case info = "Info"
  case warning = "Warning"
  case error = "Error"
}

enum DiagnosticsRedactor {
  static func redacted(_ message: String) -> String {
    var result = message
    let replacements = [
      #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#: "[redacted email]",
      #"Bearer\s+[A-Za-z0-9._\-]+"#: "Bearer [redacted token]",
      #"\beyJ[A-Za-z0-9._\-]{20,}\b"#: "[redacted token]",
      #"\b[A-Za-z0-9_\-]{32,}\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}\b"#: "[redacted token]"
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

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    source: DiagnosticSource,
    severity: DiagnosticSeverity,
    title: String,
    message: String?
  ) {
    self.id = id
    self.timestamp = timestamp
    self.source = source
    self.severity = severity
    self.title = title
    self.message = message
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
    message: String? = nil
  ) {
    // message is redacted here, before the entry is ever constructed, so the
    // persisted copy below carries the exact same redaction as what's held
    // in memory — there's no separate persistence-time redaction step to
    // keep in sync.
    let entry = DiagnosticEntry(
      source: source,
      severity: severity,
      title: title,
      message: message.map(Self.redacted)
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

    return Array(entries.prefix(maxEntries))
  }
}
