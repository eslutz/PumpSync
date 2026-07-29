import Foundation
import Observation

struct SyncMetadata: Codable, Equatable {
  var lastAttemptAt: Date?
  /// The actual wall-clock time the last sync completed successfully — used
  /// for staleness checks and "last synced" UI display. Deliberately
  /// separate from `syncWatermark`: that field is intentionally set earlier
  /// than "now" (see its doc comment), and reusing it here made every sync
  /// look ~24h stale the instant it finished, triggering an immediate
  /// re-sync on every subsequent cold launch.
  var lastSuccessfulSyncAt: Date?
  var lastSampleCount: Int
  var lastImportedCount: Int
  var lastErrorMessage: String?
  var initialImportRange: InitialImportRange
  /// The point up to which data is known to be imported, used as the next
  /// sync's `minDate`. Set from the server's effective sync window end minus
  /// a safety overlap (see `SyncCoordinator.watermarkOverlap`), not from
  /// `lastSuccessfulSyncAt` — the two serve different purposes and must not
  /// share a value.
  var syncWatermark: Date?

  private enum CodingKeys: String, CodingKey {
    case lastAttemptAt
    case lastSuccessfulSyncAt
    case lastSampleCount
    case lastImportedCount
    case lastErrorMessage
    case initialImportRange
    case syncWatermark
  }

  init(
    lastAttemptAt: Date?,
    lastSuccessfulSyncAt: Date?,
    lastSampleCount: Int,
    lastImportedCount: Int,
    lastErrorMessage: String?,
    initialImportRange: InitialImportRange = .default,
    syncWatermark: Date? = nil
  ) {
    self.lastAttemptAt = lastAttemptAt
    self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    self.lastSampleCount = lastSampleCount
    self.lastImportedCount = lastImportedCount
    self.lastErrorMessage = lastErrorMessage
    self.initialImportRange = initialImportRange
    self.syncWatermark = syncWatermark ?? lastSuccessfulSyncAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
    lastSuccessfulSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt)
    lastSampleCount = try container.decode(Int.self, forKey: .lastSampleCount)
    lastImportedCount = try container.decode(Int.self, forKey: .lastImportedCount)
    lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
    initialImportRange = try container.decodeIfPresent(InitialImportRange.self, forKey: .initialImportRange) ?? .default
    // Data persisted before this field existed has no syncWatermark key.
    // Falling back to lastSuccessfulSyncAt (the old, dual-purpose value) is
    // the correct one-time migration: it's exactly what the watermark would
    // already have been under the old behavior this field replaces.
    syncWatermark = try container.decodeIfPresent(Date.self, forKey: .syncWatermark) ?? lastSuccessfulSyncAt
  }
}

@MainActor
@Observable
final class SyncMetadataStore {
  private static let defaultsKey = "sync-metadata"
  private let defaults: UserDefaults

  private(set) var metadata: SyncMetadata

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.metadata = Self.load(defaults: defaults)
  }

  func recordAttempt() {
    metadata.lastAttemptAt = Date()
    metadata.lastErrorMessage = nil
    save()
  }

  /// - Parameter completedAt: The actual wall-clock time this sync
  ///   completed. Drives staleness checks and "last synced" UI display —
  ///   pass a real `Date()`, not the watermark.
  /// - Parameter watermark: The point up to which data is now known to be
  ///   imported, used as the next sync's `minDate`. Callers should pass the
  ///   server-reported effective sync window's end (minus a safety overlap),
  ///   not a client-side `Date()` taken after the request completes — using
  ///   a later, locally-captured timestamp here would create a permanent gap
  ///   between what was actually requested and what the next sync resumes
  ///   from.
  func recordSuccess(sampleCount: Int, importedCount: Int, completedAt: Date, watermark: Date) {
    metadata.lastSuccessfulSyncAt = completedAt
    metadata.syncWatermark = watermark
    metadata.lastSampleCount = sampleCount
    metadata.lastImportedCount = importedCount
    metadata.lastErrorMessage = nil
    save()
  }

  func recordFailure(_ error: Error) {
    // Redact at persist time, matching the discipline of every other
    // persisted diagnostics path — the message can contain server-supplied
    // text, and this copy lands unencrypted in UserDefaults and backups.
    metadata.lastErrorMessage = DiagnosticsLogStore.redacted(error.localizedDescription)
    save()
  }

  func setInitialImportRange(_ range: InitialImportRange) {
    metadata.initialImportRange = range
    save()
  }

  private func save() {
    if let data = try? JSONEncoder().encode(metadata) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }

  private static func load(defaults: UserDefaults) -> SyncMetadata {
    guard
      let data = defaults.data(forKey: defaultsKey),
      let metadata = try? JSONDecoder().decode(SyncMetadata.self, from: data)
    else {
      return SyncMetadata(
        lastAttemptAt: nil,
        lastSuccessfulSyncAt: nil,
        lastSampleCount: 0,
        lastImportedCount: 0,
        lastErrorMessage: nil,
        initialImportRange: .default
      )
    }

    return metadata
  }
}

#if DEBUG
extension SyncMetadataStore {
  func applyScreenshotMetadata(_ metadata: SyncMetadata) {
    self.metadata = metadata
    save()
  }
}
#endif
