import Foundation
import Observation

enum NativeDiagnosticKind: String, Codable, Sendable {
  case crash = "Crash"
  case performance = "Performance"
  case hang = "Hang"
  case cpuException = "CPU Exception"
  case diagnostic = "Diagnostic"
}

struct NativeDiagnosticEntry: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let timestamp: Date
  let kind: NativeDiagnosticKind
  let title: String
  let summary: String
  let appVersion: String
  let buildNumber: String
  var report: NativeDiagnosticReport? = nil

  init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    kind: NativeDiagnosticKind,
    title: String,
    summary: String,
    appVersion: String,
    buildNumber: String,
    report: NativeDiagnosticReport? = nil
  ) {
    self.id = id
    self.timestamp = timestamp
    self.kind = kind
    self.title = DiagnosticsLogStore.redacted(title)
    self.summary = DiagnosticsLogStore.redacted(summary)
    self.appVersion = DiagnosticsLogStore.redacted(appVersion)
    self.buildNumber = DiagnosticsLogStore.redacted(buildNumber)
    self.report = report
  }
}

@MainActor
@Observable
final class NativeDiagnosticsStore {
  private static let defaultsKey = "native-diagnostics"
  private static let maxEntries = 50

  private let defaults: UserDefaults
  private let directory: URL?
  private(set) var storageMessage: String?
  private(set) var entries: [NativeDiagnosticEntry]

  init(defaults: UserDefaults = .standard, directory: URL? = nil) {
    self.defaults = defaults
    self.directory = directory ?? (defaults === UserDefaults.standard
      ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("NativeDiagnostics", isDirectory: true) : nil)
    entries = []
    if let directory = self.directory, FileManager.default.fileExists(atPath: directory.appendingPathComponent("reports.json").path) {
      do {
        let data = try Data(contentsOf: directory.appendingPathComponent("reports.json"))
        entries = try JSONDecoder().decode([NativeDiagnosticEntry].self, from: data).prefix(Self.maxEntries).map(Self.sanitized)
      } catch {
        storageMessage = "Performance diagnostics are temporarily unavailable. Existing reports have been preserved."
        return
      }
    } else {
      entries = Self.load(defaults: defaults).map(Self.sanitized)
    }
    save()
  }

  private static func sanitized(_ entry: NativeDiagnosticEntry) -> NativeDiagnosticEntry {
    let report = entry.report.flatMap { report in
      (try? JSONSerialization.jsonObject(with: Data(report.json.utf8))).map { NativeDiagnosticReport.make(from: $0) }
    }
    return NativeDiagnosticEntry(id: entry.id, timestamp: entry.timestamp, kind: entry.kind,
      title: entry.title, summary: entry.summary, appVersion: entry.appVersion, buildNumber: entry.buildNumber, report: report)
  }

  func reloadIfUnavailable() {
    guard storageMessage != nil, let directory else { return }
    if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("reports.json").path) {
      // Initial migration failed before creating a file. The in-memory/legacy
      // entries are still authoritative and must be retried, not discarded.
      storageMessage = nil
      _ = save()
      return
    }
    do {
      let data = try Data(contentsOf: directory.appendingPathComponent("reports.json"))
      let loaded = try JSONDecoder().decode([NativeDiagnosticEntry].self, from: data)
      entries = loaded.prefix(Self.maxEntries).map(Self.sanitized)
      storageMessage = nil
    } catch { /* Preserve inaccessible or malformed reports for a later recovery. */ }
  }

  func record(_ entry: NativeDiagnosticEntry) {
    guard storageMessage == nil else { return }
    entries.insert(Self.sanitized(entry), at: 0)
    if entries.count > Self.maxEntries {
      entries.removeLast(entries.count - Self.maxEntries)
    }
    save()
  }

  func clear() {
    guard storageMessage == nil else { return }
    let previous = entries
    entries.removeAll()
    if !save() { entries = previous }
  }

  @discardableResult
  private func save() -> Bool {
    guard storageMessage == nil else { return false }
    do {
      let data = try JSONEncoder().encode(entries)
      if var directory {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try data.write(to: directory.appendingPathComponent("reports.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        defaults.removeObject(forKey: Self.defaultsKey)
      } else {
        defaults.set(data, forKey: Self.defaultsKey)
      }
      return true
    } catch {
      storageMessage = "Performance diagnostics could not be saved. Existing reports have been preserved."
      return false
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
