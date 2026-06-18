import Foundation
import Observation

enum DiagnosticSource: String, CaseIterable, Identifiable {
  case auth = "Sign in"
  case sync = "Sync"
  case credential = "Tandem Credentials"
  case health = "Apple Health"
  case backgroundSync = "Background Sync"
  case api = "API"

  var id: String { rawValue }
}

enum DiagnosticSeverity: String {
  case info = "Info"
  case warning = "Warning"
  case error = "Error"
}

struct DiagnosticEntry: Identifiable, Equatable {
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

  private(set) var entries: [DiagnosticEntry] = []

  func record(
    source: DiagnosticSource,
    severity: DiagnosticSeverity = .info,
    title: String,
    message: String? = nil
  ) {
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
  }

  func record(error: Error, source: DiagnosticSource, title: String) {
    record(source: source, severity: .error, title: title, message: error.localizedDescription)
  }

  func clear() {
    entries.removeAll()
  }

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
