import Foundation
import Observation

enum NativeDiagnosticKind: String, Codable, CaseIterable {
  case crash = "Crash"
  case performance = "Performance"
}

struct NativeDiagnosticEntry: Identifiable, Codable, Equatable {
  let id: UUID
  let timestamp: Date
  let kind: NativeDiagnosticKind
  let title: String
  let summary: String
  let appVersion: String
  let buildNumber: String

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    kind: NativeDiagnosticKind,
    title: String,
    summary: String,
    appVersion: String,
    buildNumber: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.kind = kind
    self.title = title
    self.summary = DiagnosticsLogStore.redacted(summary)
    self.appVersion = appVersion
    self.buildNumber = buildNumber
  }
}

@MainActor
@Observable
final class NativeDiagnosticsStore {
  private static let defaultsKey = "native-diagnostics"
  private static let maxEntries = 50

  private let defaults: UserDefaults
  private(set) var entries: [NativeDiagnosticEntry]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.entries = Self.load(defaults: defaults)
  }

  func record(_ entry: NativeDiagnosticEntry) {
    entries.insert(entry, at: 0)
    if entries.count > Self.maxEntries {
      entries.removeLast(entries.count - Self.maxEntries)
    }
    save()
  }

  func clear() {
    entries.removeAll()
    defaults.removeObject(forKey: Self.defaultsKey)
  }

  private func save() {
    if let data = try? JSONEncoder().encode(entries) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }

  private static func load(defaults: UserDefaults) -> [NativeDiagnosticEntry] {
    guard
      let data = defaults.data(forKey: defaultsKey),
      let entries = try? JSONDecoder().decode([NativeDiagnosticEntry].self, from: data)
    else {
      return []
    }

    return Array(entries.prefix(maxEntries))
  }
}

#if DEBUG
extension NativeDiagnosticsStore {
  func applyScreenshotEntries(_ entries: [NativeDiagnosticEntry]) {
    self.entries = entries
  }
}
#endif
