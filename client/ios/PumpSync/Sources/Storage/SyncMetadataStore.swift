import Foundation
import Observation

struct SyncMetadata: Codable, Equatable {
  var lastAttemptAt: Date?
  var lastSuccessfulSyncAt: Date?
  var lastSampleCount: Int
  var lastImportedCount: Int
  var lastErrorMessage: String?
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

  func recordSuccess(sampleCount: Int, importedCount: Int) {
    metadata.lastSuccessfulSyncAt = Date()
    metadata.lastSampleCount = sampleCount
    metadata.lastImportedCount = importedCount
    metadata.lastErrorMessage = nil
    save()
  }

  func recordFailure(_ error: Error) {
    metadata.lastErrorMessage = error.localizedDescription
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
        lastErrorMessage: nil
      )
    }

    return metadata
  }
}
