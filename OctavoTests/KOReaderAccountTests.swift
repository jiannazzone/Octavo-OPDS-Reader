import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// The KOReader sync account as the app keeps it (chunk 5 of
/// `docs/notes/koreader-sync-plan.md`): its ID in the list, everything else
/// in the Keychain, and each catalog's switch.
@MainActor
@Suite(.temporaryFiles)
struct KOReaderAccountTests {
    let id = "koreader-test-\(UUID().uuidString)"
    var folder: URL { URL.testDirectory.appending(path: "KOReaderAccount", directoryHint: .isDirectory) }
    var store: ServerStore { ServerStore(fileURL: folder.appending(path: "Servers.json")) }
    var positions: URL { folder.appending(path: "ReadingPositions", directoryHint: .isDirectory) }

    static let account = KOSyncAccount(
        address: URL(string: "https://nas.lan/api/koreader/0123456789abcdef")!,
        key: KOSyncKey(username: "adam", password: "secret")
    )

    /// The address may carry a key and the username may be one (Kavita's,
    /// Komga's), so the list holds neither.
    @Test func theListKeepsOnlyTheAccountsID() throws {
        defer { try? ServerCredentials.removeAll(serverID: id) }
        try KeychainKOSyncAccountStore(accountID: id).save(Self.account)
        try store.setKOReader(SavedKOReaderAccount(id: id))

        let written = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(written.contains(id))
        for secret in ["adam", "0123456789abcdef", Self.account.key.key, "nas.lan"] {
            #expect(!written.contains(secret))
        }
        #expect(!String(describing: Self.account).contains("adam"))
        #expect(!String(describing: Self.account).contains("0123456789abcdef"))

        let connection = KOReaderConnection()
        connection.load(store.load().koreader, servers: store, positions: positions)
        #expect(connection.account?.id == id)
        #expect(connection.account?.username == "adam")
        #expect(connection.account?.host == "nas.lan")
        #expect(connection.account?.client.baseURL == Self.account.address)
    }

    /// Wiped from the Keychain (a restore to another iPhone): signed out.
    @Test func anAccountTheKeychainLostIsForgotten() throws {
        try store.setKOReader(SavedKOReaderAccount(id: id))
        let connection = KOReaderConnection()
        connection.load(store.load().koreader, servers: store, positions: positions)
        #expect(connection.account == nil)
        #expect(store.load().koreader == nil)
    }

    /// Lists and servers saved before KOReader sync still read.
    @Test func aListFromBeforeStillReads() throws {
        let old = #"{"servers":[{"id":"server-1","kind":"opds","address":"http://nas.lan/opds","name":"Calibre","syncsProgress":false}],"chosen":"server-1"}"#
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(old.utf8).write(to: store.fileURL)
        let saved = try store.read()
        #expect(saved.koreader == nil)
        #expect(saved.servers.first?.koreaderSync == nil)
        #expect(saved.servers.first?.libraryServer()?.syncsWithKOReader == false)
    }

    /// A list that can't be read stays as it is: replacing it with one that
    /// holds only the account would leave the sweep to delete every server's
    /// sign-in.
    @Test func signingInLeavesAListThatCantBeRead() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.fileURL)

        #expect(throws: (any Error).self) { try store.setKOReader(SavedKOReaderAccount(id: id)) }
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == "{ not json")
    }

    /// The launch sweep keeps the account's key and pin, and only while the
    /// list has it.
    @Test func theSweepKeepsTheAccount() throws {
        defer { try? ServerCredentials.removeAll(serverID: id) }
        try KeychainKOSyncAccountStore(accountID: id).save(Self.account)
        try KeychainCertificatePinStore(serverID: id).save(CertificatePin(sha256: Data(repeating: 1, count: 32)))
        try store.setKOReader(SavedKOReaderAccount(id: id))

        try KeychainSweep.run(servers: store) { $0 == id }
        #expect(try KeychainKOSyncAccountStore(accountID: id).load() == Self.account)
        #expect(try KeychainCertificatePinStore(serverID: id).load() != nil)

        try store.setKOReader(nil)
        try KeychainSweep.run(servers: store) { $0 == id }
        #expect(try KeychainKOSyncAccountStore(accountID: id).load() == nil)
        #expect(try KeychainCertificatePinStore(serverID: id).load() == nil)
    }

    /// Sign out takes the account from the list, the Keychain and the
    /// app, and what its server last said with it.
    @Test func signingOutForgetsTheAccount() throws {
        defer { try? ServerCredentials.removeAll(serverID: id) }
        let shell = makeShell()
        try KeychainKOSyncAccountStore(accountID: id).save(Self.account)
        try shell.servers.setKOReader(SavedKOReaderAccount(id: id))
        let account = KOReaderAccount(id: id, account: Self.account, positions: shell.places.store.directory, deviceID: "test")
        shell.koreader.connect(account)
        try FileManager.default.createDirectory(at: account.places.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: account.places.file)

        shell.serverActions.signOutOfKOReader()

        #expect(shell.koreader.account == nil)
        #expect(shell.servers.load().koreader == nil)
        #expect(try KeychainKOSyncAccountStore(accountID: id).load() == nil)
        #expect(!FileManager.default.fileExists(atPath: account.places.file.path))
    }

    /// A catalog's switch is saved with it and reaches its library.
    @Test func aCatalogsSwitchIsKept() throws {
        let shell = makeShell()
        let saved = SavedServer(id: .test, kind: .opds, address: "http://nas.lan/opds", name: "Calibre")
        try shell.servers.save(saved)
        shell.library.add(try #require(saved.libraryServer()))

        shell.serverActions.setKOReaderSync(.test, true)
        #expect(shell.servers.load()[.test]?.koreaderSync == true)
        #expect(shell.library.server(.test)?.syncsWithKOReader == true)

        shell.serverActions.setKOReaderSync(.test, false)
        #expect(shell.servers.load()[.test]?.koreaderSync == false)
        #expect(shell.library.server(.test)?.syncsWithKOReader == false)
    }

    /// Question 4: an EPUB from a catalog that syncs, not downloaded, shows
    /// no place until it is. Everything else shows its place as before.
    @Test func aBookThatWaitsForItsDownload() throws {
        let shell = makeShell()
        let url = URL(string: "http://nas.lan/opds")!
        shell.library.add(LibraryServer(
            id: .test, name: "Calibre", source: OPDSSource(catalogURL: url, transport: ServerTransport(server: url)),
            syncsWithKOReader: true
        ))
        func book(_ format: String) -> SourcedBook {
            .test(LibraryBook(
                id: LibraryBookID(rawValue: format), title: "Moby-Dick",
                files: [LibraryFile(id: LibraryFileID(rawValue: format), format: format, isPrimary: true)]
            ))
        }
        let epub = book("epub")

        // No account yet: nothing waits.
        #expect(!shell.waitsForDownload(epub))
        shell.koreader.connect(KOReaderAccount(id: id, account: Self.account, positions: shell.places.store.directory, deviceID: "test"))
        #expect(shell.waitsForDownload(epub))
        // Not an EPUB, or from Files, or the catalog switched off.
        #expect(!shell.waitsForDownload(book("pdf")))
        #expect(!shell.waitsForDownload(SourcedBook(source: .files, book: epub.book)))
        shell.library.setSyncsWithKOReader(.test, false)
        #expect(!shell.waitsForDownload(epub))
    }
}
