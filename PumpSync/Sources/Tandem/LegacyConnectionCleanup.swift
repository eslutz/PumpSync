import Foundation
import Security

enum LegacyConnectionCleanup {
  /// Remove service credentials after upgrading, including credentials from interrupted
  /// connection switches. Query item attributes only so secret values never enter memory.
  static func run(in keychain: SecureKeychainStore, defaults: UserDefaults = .standard) throws {
    let marker = "direct.legacyServiceRemoved"
    guard !defaults.bool(forKey: marker) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychain.service,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess {
      guard let items = result as? [[String: Any]] else { throw KeychainStoreError.invalidData }
      for item in items {
        guard let account = item[kSecAttrAccount as String] as? String else { throw KeychainStoreError.invalidData }
        if account.hasPrefix("backend.") || account.hasPrefix("connection.") || account.hasPrefix("device-proof.") {
          try keychain.delete(account: account)
        }
      }
    } else if status != errSecItemNotFound {
      throw KeychainStoreError.unexpectedStatus(status)
    }
    for preference in ["backend.mode", "backend.selfHostedBaseURL", "backend.hostedEnvironment"] {
      defaults.removeObject(forKey: preference)
    }
    defaults.set(true, forKey: marker)
  }
}
