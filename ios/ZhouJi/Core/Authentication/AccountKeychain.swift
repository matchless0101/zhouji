import Foundation
import Security

@MainActor
protocol AccountSessionStoring {
    func read() throws -> AccountSession?
    func save(_ session: AccountSession) throws
    func clear() throws
}

struct AccountKeychain: AccountSessionStoring {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.matchless.ZhouJi.account",
         kSecAttrAccount as String: "session"]
    }

    func read() throws -> AccountSession? {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw AccountError.keychain }
        do { return try JSONDecoder().decode(AccountSession.self, from: data) }
        catch { throw AccountError.keychain }
    }

    func save(_ session: AccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let updates: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            let attributes = query.merging(updates) { _, new in new }
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw AccountError.keychain }
        } else if status != errSecSuccess { throw AccountError.keychain }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AccountError.keychain }
    }
}
