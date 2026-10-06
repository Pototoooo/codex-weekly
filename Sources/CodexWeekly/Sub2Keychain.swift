import Foundation
import Security

enum Sub2Keychain {
    private static func query(_ endpoint: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.codex.weekly.sub2api",
         kSecAttrAccount as String: endpoint.absoluteString]
    }
    static func read(endpoint: URL) throws -> String {
        var q = query(endpoint)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { throw Sub2Error.missingKey }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw Sub2Error.keychain }
        return key
    }
    static func save(_ configuration: Sub2Configuration) throws {
        let q = query(configuration.endpoint)
        // Keep the item available after the login keychain is first unlocked.
        // This avoids a password prompt on every quota refresh or source switch.
        // Updating the accessibility class of an existing item can trigger an
        // authorization prompt or fail for items created by an older build.
        // Keep that update limited to the value; new items use the improved
        // accessibility class below.
        let attributes: [String: Any] = [
            kSecValueData as String: Data(configuration.key.utf8)
        ]
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = q.merging(attributes) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Sub2Error.keychain }
    }
}
