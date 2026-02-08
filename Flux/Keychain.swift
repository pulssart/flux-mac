// Keychain.swift
// Simple Keychain helpers for storing sensitive data like API keys

import Foundation
import Security
import LocalAuthentication

enum KeychainService {
    static func save(service: String, account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Try update first
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        return false
    }

    static func read(service: String, account: String) -> String? {
        // Créer un contexte LAContext qui n'autorise pas l'interaction utilisateur
        let context = LAContext()
        context.interactionNotAllowed = true

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Utiliser le contexte LAContext au lieu de kSecUseAuthenticationUI (deprecated)
            kSecUseAuthenticationContext as String: context
        ]
        // Utiliser le Data Protection Keychain quand disponible (macOS 10.15+)
        query[kSecUseDataProtectionKeychain as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}


