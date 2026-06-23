import CryptoKit
import Foundation

final class ImportedSampleLedger {
  private static let hmacKeyAccount = "imported-sample-ledger-hmac-key"
  private static let defaultsKey = "imported-sample-ledger"
  private static let maxEntries = 5000
  private static let retentionInterval: TimeInterval = 370 * 24 * 60 * 60

  private let keychain: SecureKeychainStore
  private let defaults: UserDefaults

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

    for sample in samples {
      ledger[try digest(for: sample.externalId)] = timestamp
    }

    defaults.set(prune(ledger, now: importedAt), forKey: Self.defaultsKey)
  }

  private func loadLedger() -> [String: TimeInterval] {
    defaults.dictionary(forKey: Self.defaultsKey) as? [String: TimeInterval] ?? [:]
  }

  private func prune(_ ledger: [String: TimeInterval], now: Date) -> [String: TimeInterval] {
    let minimumTimestamp = now.addingTimeInterval(-Self.retentionInterval).timeIntervalSince1970
    let retained = ledger.filter { $0.value >= minimumTimestamp }

    if retained.count <= Self.maxEntries {
      return retained
    }

    return retained
      .sorted { $0.value > $1.value }
      .prefix(Self.maxEntries)
      .reduce(into: [String: TimeInterval]()) { result, entry in
        result[entry.key] = entry.value
      }
  }

  private func digest(for externalId: String) throws -> String {
    let key = SymmetricKey(data: try hmacKeyData())
    let authenticationCode = HMAC<SHA256>.authenticationCode(for: Data(externalId.utf8), using: key)
    return Data(authenticationCode).map { String(format: "%02x", $0) }.joined()
  }

  private func hmacKeyData() throws -> Data {
    if let data = try keychain.readData(account: Self.hmacKeyAccount) {
      return data
    }

    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    try keychain.writeData(data, account: Self.hmacKeyAccount)
    return data
  }
}
