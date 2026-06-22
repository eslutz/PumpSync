import Foundation
import Security

struct SecureKeychainStore {
  let service: String

  func readData(account: String) throws -> Data? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecItemNotFound {
      return nil
    }

    guard status == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(status)
    }

    guard let data = result as? Data else {
      throw KeychainStoreError.invalidData
    }

    return data
  }

  func writeData(_ data: Data, account: String) throws {
    try delete(account: account)

    var query = baseQuery(account: account)
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

enum KeychainStoreError: LocalizedError {
  case invalidData
  case unexpectedStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidData:
      return "The secure item could not be decoded."
    case .unexpectedStatus(let status):
      return "Keychain returned status \(status)."
    }
  }
}
