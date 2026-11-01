import Foundation
import Security

/// One generic-password item in the Keychain, as raw bytes.
///
/// Items are this device's only (`…AfterFirstUnlockThisDeviceOnly`): never
/// synced, never in backups, and readable in the background once the iPhone
/// has been unlocked after a restart. Writes replace the item in place
/// (`SecItemUpdate`, or `SecItemAdd` when there is none), so a crash leaves
/// either the old value or the new one, never neither.
struct KeychainItem: Sendable {
    var service: String
    var account: String

    func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    func write(_ data: Data) throws {
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        for _ in 0..<2 {
            let updated = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            if updated == errSecSuccess { return }
            guard updated == errSecItemNotFound else { throw KeychainError(status: updated) }
            let added = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
            if added == errSecSuccess { return }
            // Someone added it in between: update that one.
            guard added == errSecDuplicateItem else { throw KeychainError(status: added) }
        }
        throw KeychainError(status: errSecDuplicateItem)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    /// Deletes every item of `service`, whatever its account.
    static func deleteAll(service: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public struct KeychainError: Error, Equatable, CustomStringConvertible {
    public var status: OSStatus

    public var description: String {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}
