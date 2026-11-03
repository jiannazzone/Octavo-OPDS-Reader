import Foundation
@testable import OctavoKit
import Security
import Testing
@testable import Octavo

/// The real Keychain, in the app's own process (the simulator), where the
/// app's entitlements and data protection apply.
@Suite(.serialized, .temporaryFiles)
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
        let secrets = KeychainCatalogSecretStore(serverID: serverID)
        let neighbour = KeychainPasswordStore(serverID: serverID + "-other")
        try await tokens.save(BookOrbitCredentials(accessToken: "a", refreshToken: "r"))
        try await passwords.save(PasswordCredentials(username: "octavo", password: "secret"))
        try pins.save(CertificatePin(sha256: Data(repeating: 7, count: 32)))
        try secrets.save(OPDSURLSecret("0123456789abcdef"))
        try await neighbour.save(PasswordCredentials(username: "other", password: "kept"))

        #expect(try await passwords.load()?.password == "secret")
        #expect(try pins.load()?.sha256 == Data(repeating: 7, count: 32))
        #expect(try secrets.load()?.value == "0123456789abcdef")

        try ServerCredentials.removeAll(serverID: serverID)

        #expect(try await tokens.load() == nil)
        #expect(try await passwords.load() == nil)
        #expect(try pins.load() == nil)
        #expect(try secrets.load() == nil)
        #expect(try await neighbour.load()?.password == "kept")
        try ServerCredentials.removeAll(serverID: serverID + "-other")
    }

    /// Keychain items outlive the app; the first launch after an install
    /// deletes them, once.
    @Test func reinstallStartsSignedOut() async throws {
        let defaults = UserDefaults.testSuite("keychain-test")
        let tokens = KeychainBookOrbitTokenStore(serverID: serverID)
        try await tokens.save(BookOrbitCredentials(accessToken: "left over"))

        try ServerCredentials.removeLeftoversAfterInstall(defaults: defaults)
        #expect(try await tokens.load() == nil)

        try await tokens.save(BookOrbitCredentials(accessToken: "signed in after"))
        try ServerCredentials.removeLeftoversAfterInstall(defaults: defaults)
        #expect(try await tokens.load()?.accessToken == "signed in after")
        try ServerCredentials.removeAll(serverID: serverID)
    }

    // MARK: Step 16

    /// The launch sweep: only the saved server keeps secrets. Gone: a
    /// server whose Remove server couldn't clear the Keychain, and a setup
    /// left half way. (Scoped to this test's servers: the simulator's own
    /// and other tests' stay.)
    @Test func theLaunchSweepKeepsOnlyTheSavedServer() async throws {
        let prefix = "sweep-test-\(UUID().uuidString)-"
        let saved = SavedServer(id: LibrarySourceID(rawValue: prefix + "saved"), kind: .opds, address: "http://nas.lan/opds", name: "COPS")
        let removed = prefix + "removed"
        let abandoned = prefix + "abandoned"
        let debug = "debug-\(prefix)local"
        let all = [saved.id.rawValue, removed, abandoned, debug]
        defer { for id in all { try? ServerCredentials.removeAll(serverID: id) } }
        for id in all {
            try await KeychainPasswordStore(serverID: id).save(PasswordCredentials(username: "u", password: "p"))
            try KeychainCertificatePinStore(serverID: id).save(CertificatePin(sha256: Data(repeating: 1, count: 32)))
        }
        try await KeychainBookOrbitTokenStore(serverID: abandoned).save(BookOrbitCredentials(accessToken: "a"))
        try KeychainCatalogSecretStore(serverID: removed).save(OPDSURLSecret("0123456789abcdef"))
        let store = ServerStore(fileURL: URL.testDirectory.appending(path: "Server.json"))
        try store.save(saved)

        try KeychainSweep.run(servers: store) { $0.hasPrefix(prefix) || $0 == debug }

        #expect(try await KeychainPasswordStore(serverID: saved.id.rawValue).load() != nil)
        #expect(try KeychainCertificatePinStore(serverID: saved.id.rawValue).load() != nil)
        for id in [removed, abandoned] {
            #expect(try await KeychainPasswordStore(serverID: id).load() == nil)
            #expect(try KeychainCertificatePinStore(serverID: id).load() == nil)
        }
        #expect(try await KeychainBookOrbitTokenStore(serverID: abandoned).load() == nil)
        #expect(try KeychainCatalogSecretStore(serverID: removed).load() == nil)
        // The debug servers keep their sign-ins in debug builds.
        #expect(try await KeychainPasswordStore(serverID: debug).load() != nil)

        // No saved server: nothing is kept.
        try store.remove()
        try KeychainSweep.run(servers: store) { $0.hasPrefix(prefix) }
        #expect(try await KeychainPasswordStore(serverID: saved.id.rawValue).load() == nil)
    }

    /// A saved server that can't be read isn't "no server": nothing goes.
    @Test func theSweepDeletesNothingWhileTheSavedServerCantBeRead() async throws {
        let prefix = "sweep-test-\(UUID().uuidString)-"
        let id = prefix + "server"
        defer { try? ServerCredentials.removeAll(serverID: id) }
        try await KeychainPasswordStore(serverID: id).save(PasswordCredentials(username: "u", password: "p"))
        let file = URL.testDirectory.appending(path: "Server.json")
        try Data("{ not json".utf8).write(to: file)

        #expect(throws: (any Error).self) { try KeychainSweep.run(servers: ServerStore(fileURL: file)) { $0.hasPrefix(prefix) } }
        #expect(try await KeychainPasswordStore(serverID: id).load() != nil)
    }

    /// Signed out, but the Keychain couldn't delete the sign-in then: the
    /// next launch does. The certificate and a catalog's key stay with the
    /// server.
    @Test func aServerSignedOutOfLosesItsSignInAtLaunch() async throws {
        let id = "sweep-test-\(UUID().uuidString)"
        defer { try? ServerCredentials.removeAll(serverID: id) }
        var saved = SavedServer(id: LibrarySourceID(rawValue: id), kind: .opds, address: "http://nas.lan/api/opds/{key}", name: "Kavita")
        try await KeychainBookOrbitTokenStore(serverID: id).save(BookOrbitCredentials(accessToken: "a"))
        try await KeychainPasswordStore(serverID: id).save(PasswordCredentials(username: "u", password: "p"))
        try KeychainCertificatePinStore(serverID: id).save(CertificatePin(sha256: Data(repeating: 1, count: 32)))
        try KeychainCatalogSecretStore(serverID: id).save(OPDSURLSecret("0123456789abcdef"))
        let store = ServerStore(fileURL: URL.testDirectory.appending(path: "Server.json"))
        try store.save(saved)

        try KeychainSweep.run(servers: store) { $0 == id }
        #expect(try await KeychainPasswordStore(serverID: id).load() != nil, "still signed in")

        saved.signedOut = true
        try store.save(saved)
        try KeychainSweep.run(servers: store) { $0 == id }
        #expect(try await KeychainBookOrbitTokenStore(serverID: id).load() == nil)
        #expect(try await KeychainPasswordStore(serverID: id).load() == nil)
        #expect(try KeychainCertificatePinStore(serverID: id).load() != nil)
        #expect(try KeychainCatalogSecretStore(serverID: id).load() != nil)
    }

    /// A catalog address can carry more than one secret; one is still
    /// stored the way step 8 stored Kavita's key, a JSON string.
    @Test func catalogSecretsKeepSeveralAndStayReadable() throws {
        let store = KeychainCatalogSecretStore(serverID: serverID)
        defer { try? ServerCredentials.removeAll(serverID: serverID) }
        try store.save(OPDSURLSecret(values: ["stump_0123456789", "token-abcdefgh"]))
        #expect(try store.load()?.values == ["stump_0123456789", "token-abcdefgh"])

        try store.save(OPDSURLSecret("0123456789abcdef"))
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: ServerCredentials.catalogSecretService,
            kSecAttrAccount: serverID,
            kSecReturnData: true,
            kSecUseDataProtectionKeychain: true,
        ]
        var data: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &data) == errSecSuccess)
        #expect((data as? Data).map { String(decoding: $0, as: UTF8.self) } == #""0123456789abcdef""#)
        #expect(try store.load()?.values == ["0123456789abcdef"])
    }
}
