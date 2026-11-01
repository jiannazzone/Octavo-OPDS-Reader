import Foundation
@testable import OctavoKit
import Security
import Testing

/// The real Keychain, in the app's own process (the simulator), where the
/// app's entitlements and data protection apply.
@Suite(.serialized)
struct KeychainTests {
    let serverID = "keychain-test-\(UUID().uuidString)"

    private func attributes(service: String) throws -> [String: Any] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: serverID,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return try #require(result as? [String: Any])
    }

    @Test func tokensRoundTripAndReplaceInPlace() async throws {
        let store = KeychainBookOrbitTokenStore(serverID: serverID)
        #expect(try await store.load() == nil)

        let first = BookOrbitCredentials(accessToken: "access-1", refreshToken: "refresh-1", sessionID: 7)
        try await store.save(first)
        #expect(try await store.load() == first)
        let created = try attributes(service: ServerCredentials.tokenService)[kSecAttrCreationDate as String] as? Date

        let rotated = BookOrbitCredentials(accessToken: "access-2", refreshToken: "refresh-2", sessionID: 7)
        try await store.save(rotated)
        #expect(try await store.load() == rotated)
        // Updated, not deleted and added again: no moment with nothing stored.
        #expect(try attributes(service: ServerCredentials.tokenService)[kSecAttrCreationDate as String] as? Date == created)

        try await store.save(nil)
        #expect(try await store.load() == nil)
    }

    /// This device only, readable in the background after the first unlock,
    /// never synced to iCloud.
    @Test func itemsStayOnThisDevice() async throws {
        try await KeychainBookOrbitTokenStore(serverID: serverID).save(BookOrbitCredentials(accessToken: "a"))
        let found = try attributes(service: ServerCredentials.tokenService)
        #expect(found[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect((found[kSecAttrSynchronizable as String] as? Bool ?? false) == false)
        try ServerCredentials.removeAll(serverID: serverID)
    }

    /// An item that no longer decodes is dropped (sign in again), not an
    /// error on every request.
    @Test func undecodableItemsAreDropped() async throws {
        let store = KeychainBookOrbitTokenStore(serverID: serverID)
        try await store.save(BookOrbitCredentials(accessToken: "a"))
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: ServerCredentials.tokenService,
            kSecAttrAccount: serverID,
        ]
        #expect(SecItemUpdate(query as CFDictionary, [kSecValueData: Data("not json".utf8)] as CFDictionary) == errSecSuccess)

        #expect(try await store.load() == nil)
        #expect(try await store.load() == nil)
    }

    @Test func removeServerForgetsEverything() async throws {
        let tokens = KeychainBookOrbitTokenStore(serverID: serverID)
        let passwords = KeychainPasswordStore(serverID: serverID)
        let pins = KeychainCertificatePinStore(serverID: serverID)
        let neighbour = KeychainPasswordStore(serverID: serverID + "-other")
        try await tokens.save(BookOrbitCredentials(accessToken: "a", refreshToken: "r"))
        try await passwords.save(PasswordCredentials(username: "octavo", password: "secret"))
        try pins.save(CertificatePin(sha256: Data(repeating: 7, count: 32)))
        try await neighbour.save(PasswordCredentials(username: "other", password: "kept"))

        #expect(try await passwords.load()?.password == "secret")
        #expect(try pins.load()?.sha256 == Data(repeating: 7, count: 32))

        try ServerCredentials.removeAll(serverID: serverID)

        #expect(try await tokens.load() == nil)
        #expect(try await passwords.load() == nil)
        #expect(try pins.load() == nil)
        #expect(try await neighbour.load()?.password == "kept")
        try ServerCredentials.removeAll(serverID: serverID + "-other")
    }

    /// Keychain items outlive the app; the first launch after an install
    /// deletes them, once.
    @Test func reinstallStartsSignedOut() async throws {
        let defaults = try #require(UserDefaults(suiteName: "keychain-test-\(UUID().uuidString)"))
        let tokens = KeychainBookOrbitTokenStore(serverID: serverID)
        try await tokens.save(BookOrbitCredentials(accessToken: "left over"))

        try ServerCredentials.removeLeftoversAfterInstall(defaults: defaults)
        #expect(try await tokens.load() == nil)

        try await tokens.save(BookOrbitCredentials(accessToken: "signed in after"))
        try ServerCredentials.removeLeftoversAfterInstall(defaults: defaults)
        #expect(try await tokens.load()?.accessToken == "signed in after")
        try ServerCredentials.removeAll(serverID: serverID)
    }
}
