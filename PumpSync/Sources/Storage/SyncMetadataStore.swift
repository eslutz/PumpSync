import Foundation
import Observation

struct SyncMetadata: Codable, Equatable {
  var lastAttemptAt: Date?
  var lastSuccessfulSyncAt: Date?
  var lastSampleCount: Int
  var lastImportedCount: Int
  var lastErrorMessage: String?
  var initialImportRange: InitialImportRange

  private enum CodingKeys: String, CodingKey {
    case lastAttemptAt
    case lastSuccessfulSyncAt
    case lastSampleCount
    case lastImportedCount
    case lastErrorMessage
    case initialImportRange
  }

  init(
    lastAttemptAt: Date?,
    lastSuccessfulSyncAt: Date?,
    lastSampleCount: Int,
    lastImportedCount: Int,
    lastErrorMessage: String?,
    initialImportRange: InitialImportRange = .default
  ) {
    self.lastAttemptAt = lastAttemptAt
    self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    self.lastSampleCount = lastSampleCount
    self.lastImportedCount = lastImportedCount
    self.lastErrorMessage = lastErrorMessage
    self.initialImportRange = initialImportRange
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
    lastSuccessfulSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt)
    lastSampleCount = try container.decode(Int.self, forKey: .lastSampleCount)
    lastImportedCount = try container.decode(Int.self, forKey: .lastImportedCount)
    lastErrorMessage = try container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
    initialImportRange = try container.decodeIfPresent(InitialImportRange.self, forKey: .initialImportRange) ?? .default
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
