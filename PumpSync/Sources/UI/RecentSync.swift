import Foundation

struct RecentSync: Identifiable, Equatable {
  enum ID: Hashable {
    case attempt(scope: UUID, operation: UUID)
    case latestSuccess(scope: UUID, completedAt: Date)
  }

  let id: ID
  let completedAt: Date
  let returned: Int?
  let saved: Int?
  let permissionSkipped: Int?

  var summary: String {
    guard let saved else { return String(localized: "Saved count unavailable") }
    if saved > 0 {
      return SyncCompletion(received: returned ?? 0, saved: saved, completedAt: completedAt).message
    }
    if returned == 0 { return String(localized: "No new samples") }
    if let returned, let permissionSkipped {
      return SyncCompletion(received: returned, saved: saved, permissionSkipped: permissionSkipped,
                            completedAt: completedAt).message
    }
    return String(localized: "No samples saved to Apple Health")
  }

  var compactSummary: String {
    guard let saved, saved > 0 else { return summary }
    let text = AttributedString(localized: "^[\(saved, format: .number) sample](inflect: true) saved")
    return String(text.inflected().characters)
  }

  static func retained(metadata: SyncMetadata, attempts: [SyncAttempt]) -> [Self] {
    let scope = metadata.historyScopeID
    let completed = attempts.filter { $0.historyScopeID == scope && $0.outcome == .completed }
    var rows = completed.compactMap { attempt -> Self? in
      guard let date = attempt.completedAt else { return nil }
      return Self(id: .attempt(scope: scope, operation: attempt.operationID), completedAt: date,
                  returned: attempt.returnedCount, saved: attempt.importedCount,
                  permissionSkipped: attempt.permissionSkippedCount)
    }
    if let success = metadata.lastSuccessfulSyncAt,
       !completed.contains(where: { attempt in
         // The metadata write precedes the terminal attempt timestamp.
         attempt.completedAt.map { attempt.startedAt <= success && success <= $0 } ?? false
       }) {
      rows.append(Self(id: .latestSuccess(scope: scope, completedAt: success), completedAt: success,
                       returned: metadata.lastSampleCount, saved: metadata.lastImportedCount,
                       permissionSkipped: metadata.lastPermissionSkippedCount))
    }
    return rows.sorted { $0.completedAt > $1.completedAt }
  }
}

struct RecentSyncDay: Identifiable {
  let id: Date
  let runs: [RecentSync]

  static func groups(for runs: [RecentSync], calendar: Calendar) -> [Self] {
    let grouped = Dictionary(grouping: runs) { calendar.startOfDay(for: $0.completedAt) }
    return grouped.keys.sorted(by: >).map { Self(id: $0, runs: grouped[$0, default: []]) }
  }

  func title(now: Date, calendar: Calendar) -> String {
    if calendar.isDate(id, inSameDayAs: now) { return String(localized: "Today") }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(id, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
    return id.formatted(date: .abbreviated, time: .omitted)
  }
}
