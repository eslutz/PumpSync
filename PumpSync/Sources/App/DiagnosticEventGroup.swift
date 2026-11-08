import Foundation

/// A single visible operation with its retained snapshots available in details.
/// Events without an operation ID remain independent, including legacy records.
struct DiagnosticEventGroup: Identifiable {
    let id: String
    let entries: [DiagnosticEntry]

    var latest: DiagnosticEntry { entries[0] }
    var timestamp: Date { latest.timestamp }
    var title: String { DiagnosticPresentation.title(for: latest) }
    var summary: String? { DiagnosticPresentation.summary(for: latest) }

    static func make(from entries: [DiagnosticEntry]) -> [DiagnosticEventGroup] {
        var keys: [String] = []
        var grouped: [String: [DiagnosticEntry]] = [:]
        for entry in entries.sorted(by: { $0.timestamp > $1.timestamp }) {
            let key = entry.syncAttempt.map { "operation:\($0.operationID)" } ?? "event:\(entry.id)"
            if grouped[key] == nil { keys.append(key) }
            grouped[key, default: []].append(entry)
        }
        return keys.compactMap { key in
            guard let entries = grouped[key], !entries.isEmpty else { return nil }
            return DiagnosticEventGroup(id: key, entries: entries)
        }
    }
}
