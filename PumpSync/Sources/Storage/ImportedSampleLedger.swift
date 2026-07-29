import CryptoKit
import Foundation

final class ImportedSampleLedger {
  private static let hmacKeyAccount = "imported-sample-ledger-hmac-key"
  private static let defaultsKey = "imported-sample-ledger"
  private static let maxEntries = 5000
  private static let retentionInterval: TimeInterval = 370 * 24 * 60 * 60

  private let keychain: SecureKeychainStore
  private let defaults: UserDefaults
  // One Keychain read per ledger instance instead of per digest: filterUnseen
  // and recordImported both digest every sample, and a synchronous Keychain
  // round trip per sample stalls the main actor for seconds on a large
  // initial import.
  private var cachedHmacKey: SymmetricKey?

  init(keychain: SecureKeychainStore, defaults: UserDefaults = .standard) {
    self.keychain = keychain
    self.defaults = defaults
  }

  func filterUnseen(_ samples: [SampleDTO]) throws -> [SampleDTO] {
    let ledger = loadLedger()
    return try samples.filter { sample in
      !ledger.keys.contains(try digest(for: sample.externalId))
    }
  }

  func recordImported(_ samples: [SampleDTO], importedAt: Date = Date()) throws {
    var ledger = loadLedger()
    let timestamp = importedAt.timeIntervalSince1970
    var batchDigests = Set<String>()

    for sample in samples {
      let sampleDigest = try digest(for: sample.externalId)
      ledger[sampleDigest] = timestamp
      batchDigests.insert(sampleDigest)
    }

    defaults.set(prune(ledger, now: importedAt, protecting: batchDigests), forKey: Self.defaultsKey)
  }

  private func loadLedger() -> [String: TimeInterval] {
    defaults.dictionary(forKey: Self.defaultsKey) as? [String: TimeInterval] ?? [:]
  }

  private func prune(_ ledger: [String: TimeInterval], now: Date, protecting protected: Set<String>) -> [String: TimeInterval] {
    let minimumTimestamp = now.addingTimeInterval(-Self.retentionInterval).timeIntervalSince1970
    let retained = ledger.filter { $0.value >= minimumTimestamp }

    if retained.count <= Self.maxEntries {
      return retained
    }

    // Never evict the batch that was just recorded: an evicted entry whose
    // sample is re-fetched inside the next sync's watermark overlap would be
    // re-imported into Apple Health as a duplicate. Equal timestamps (one
    // large import batch stamps every entry identically) are broken by key so
    // eviction is deterministic rather than following dictionary order. The
    // cap may be exceeded transiently when a single batch is larger than
    // maxEntries; the following prune shrinks it back.
    let overflow = retained.count - Self.maxEntries
    let evicted = retained
      .filter { !protected.contains($0.key) }
      .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
      .prefix(overflow)

    var result = retained
    for entry in evicted {
      result.removeValue(forKey: entry.key)
    }

    return result
  }

  private func digest(for externalId: String) throws -> String {
    let key = try hmacKey()
    let authenticationCode = HMAC<SHA256>.authenticationCode(for: Data(externalId.utf8), using: key)
    return Data(authenticationCode).map { String(format: "%02x", $0) }.joined()
  }

  private func hmacKey() throws -> SymmetricKey {
    if let cachedHmacKey {
      return cachedHmacKey
    }

    let key: SymmetricKey
    if let data = try keychain.readData(account: Self.hmacKeyAccount) {
      key = SymmetricKey(data: data)
    } else {
      key = SymmetricKey(size: .bits256)
      let data = key.withUnsafeBytes { Data($0) }
      try keychain.writeData(data, account: Self.hmacKeyAccount)
    }

    cachedHmacKey = key
    return key
  }
}
