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
    // Upsert (add, then update on duplicate) instead of delete-then-add: a
    // crash between a delete and the following add would lose the item, and
    // for the sample-ledger HMAC key that silently orphans the entire dedupe
    // ledger — re-fetched samples would be re-imported into Apple Health as
    // duplicates.
    var addQuery = baseQuery(account: account)
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return
    }

    guard addStatus == errSecDuplicateItem else {
      throw KeychainStoreError.unexpectedStatus(addStatus)
    }

    let updateAttributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, updateAttributes as CFDictionary)
    guard updateStatus == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(updateStatus)
    }
  }

  /// Preserves an existing item while upgrading it for access by a task that
  /// runs after the device has been unlocked at least once. Call only for
  /// records whose background use is intentional.
  @discardableResult
  func migrateAccessibilityToAfterFirstUnlock(account: String) throws -> Bool {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecReturnAttributes as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return false
    }
    guard status == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
    guard
      let attributes = result as? [String: Any],
      let accessibility = attributes[kSecAttrAccessible as String] as? String,
      accessibility != (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    else {
      return false
    }

    let updateAttributes: [String: Any] = [
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary, updateAttributes as CFDictionary)
    guard updateStatus == errSecSuccess else {
      throw KeychainStoreError.unexpectedStatus(updateStatus)
    }
    return true
  }

  func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)

    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  func deleteAll() throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service
    ]
    let status = SecItemDelete(query as CFDictionary)

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
