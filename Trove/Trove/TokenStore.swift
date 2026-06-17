import Foundation
import Security

/// Persists the bearer + refresh token in the iOS Keychain. Thread-safe.
final class TokenStore: @unchecked Sendable {
    private let lock = NSLock()
    private let accessKey = "ai.trovestore.accessToken"
    private let refreshKey = "ai.trovestore.refreshToken"

    var accessToken: String? { lock.withLock { Keychain.read(accessKey) } }
    var refreshToken: String? { lock.withLock { Keychain.read(refreshKey) } }
    var hasSession: Bool { accessToken != nil }

    func save(access: String, refresh: String) {
        lock.withLock {
            Keychain.set(access, for: accessKey)
            Keychain.set(refresh, for: refreshKey)
        }
    }

    func clear() {
        lock.withLock {
            Keychain.delete(accessKey)
            Keychain.delete(refreshKey)
        }
    }
}

/// Minimal generic-password Keychain helpers.
///
/// Tokens are written to a **shared access group** so the Share Extension can read
/// the same session (must match `keychain-access-groups` in both targets'
/// entitlements + the extension's `SharedKeychain`; the OS prepends the team's
/// AppIdentifierPrefix, so we store the bare suffix). Resilient: writes fall back
/// to ungrouped if the entitlement isn't provisioned, and reads check both — so
/// login never breaks and pre-sharing sessions still resolve.
enum Keychain {
    static let accessGroup = "ai.trovestore.shared"

    static func set(_ value: String, for key: String) {
        delete(key) // clear any prior copy (grouped or ungrouped)
        var add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemAdd(add as CFDictionary, nil) == errSecMissingEntitlement {
            add.removeValue(forKey: kSecAttrAccessGroup as String)
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func read(_ key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data { return String(data: data, encoding: .utf8) }
        // Fallback to an ungrouped item (written before sharing, or no entitlement).
        query.removeValue(forKey: kSecAttrAccessGroup as String)
        result = nil
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    static func delete(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }
}
