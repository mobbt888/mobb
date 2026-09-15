import Foundation
import Security

/// Keychain 最小封装，仅做 token 的读、写、删。
///
/// 鉴权 token **不要**放 UserDefaults：那里是明文且会被 iTunes / iCloud 备份带走。
enum TokenStore {

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.example.cloudphone"
    }

    static var token: String? {
        get { string(for: "access_token") }
        set {
            guard let newValue else {
                try? delete("access_token")
                return
            }
            try? set(newValue, for: "access_token")
        }
    }

    // MARK: - 原语

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) throws {
        try? delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenStoreError.unhandled(status)
        }
    }

    static func delete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.unhandled(status)
        }
    }
}

enum TokenStoreError: Error, LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status): return "Keychain 操作失败（OSStatus \(status)）"
        }
    }
}
