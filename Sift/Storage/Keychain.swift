import Foundation
import Security

/// Secrets live only in the login keychain: the Anthropic API key and the X
/// OAuth tokens. One generic read and write; named wrappers per secret.
enum Keychain {
    static let anthropicService = "app.sift.anthropic-api-key"
    static let xTokensService = "app.sift.x-oauth-tokens"
    private static let account = "default"

    static func read(service: String) -> String? {
        // Demo mode never sees the owner's secrets.
        if Demo.isOn { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    /// Saves the value, or deletes the item when the value is empty.
    @discardableResult
    static func save(_ value: String, service: String) -> Bool {
        if Demo.isOn { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func readKey() -> String? { read(service: anthropicService) }

    @discardableResult
    static func saveKey(_ key: String) -> Bool { save(key, service: anthropicService) }
}
