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
enum Keychain {
    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
