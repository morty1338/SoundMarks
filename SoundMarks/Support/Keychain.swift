import Foundation
import Security

/// Secrets (tokens, source usernames) are stored in the Keychain,
/// not in `UserDefaults`.
enum Keychain {
    enum Item: String {
        case lastFmUsername = "lastfm.username"
        case lastFmSessionKey = "lastfm.sessionKey"
        case spotifyRefreshToken = "spotify.refreshToken"
    }

    private static let service = "com.bibadev.musicmap"

    @discardableResult
    static func set(_ value: String?, for item: Item) -> Bool {
        guard let value, !value.isEmpty else { return remove(item) }
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }

        guard status == errSecItemNotFound else {
            Log.persistence.error("Keychain update \(item.rawValue, privacy: .public): \(status)")
            return false
        }
        let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if added != errSecSuccess {
            Log.persistence.error("Keychain add \(item.rawValue, privacy: .public): \(added)")
        }
        return added == errSecSuccess
    }

    static func string(for item: Item) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func remove(_ item: Item) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
