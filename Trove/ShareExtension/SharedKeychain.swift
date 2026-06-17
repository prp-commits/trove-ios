import Foundation
import Security

/// Reads/writes the Trove session tokens in the **shared keychain access group**
/// so the Share Extension can use the same login as the app. Mirrors the app's
/// `Keychain` (TokenStore.swift) — the access group + keys MUST stay in sync.
enum SharedKeychain {
    static let accessGroup = "ai.trovestore.shared"
    static let accessKey = "ai.trovestore.accessToken"
    static let refreshKey = "ai.trovestore.refreshToken"

    static func read(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data { return String(data: data, encoding: .utf8) }
        // Fallback without the group (tokens written before sharing existed).
        query.removeValue(forKey: kSecAttrAccessGroup as String)
        result = nil
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
