import Foundation
import OctavoKit
import Synchronization
import Testing
@testable import Octavo

/// More than one server (decision 36): each one's books, places and secrets
/// are its own, Home and Search cover them all, and an install from when
/// there could be only one carries over.
private let one = LibrarySourceID(rawValue: "server-one")
private let two = LibrarySourceID(rawValue: "server-two")

private func file(_ id: String = "17") -> LibraryFile {
    LibraryFile(id: LibraryFileID(rawValue: id), format: "epub", isPrimary: true)
}

/// The same book number on two servers is two books: BookOrbit numbers its
/// files from 1 on every server.
private func book(_ id: String = "17", _ title: String = "Moby-Dick") -> LibraryBook {
    LibraryBook(id: LibraryBookID(rawValue: id), title: title, authors: ["Herman Melville"], files: [file(id)])
}

/// A folder of its own for one test's stores.
private func folder() -> URL {
    URL.testDirectory.appending(path: "SeveralServers-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func write(_ text: String = "x", to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

@Suite(.temporaryFiles)
struct ServerStoreListTests {
    private func store() -> ServerStore {
        ServerStore(fileURL: folder().appending(path: "Servers.json"))
    }

    private func saved(_ id: LibrarySourceID, name: String = "BookOrbit") -> SavedServer {
        SavedServer(id: id, kind: .bookOrbit, address: "http://\(id.rawValue).lan", name: name)
    }

    @Test func addsInOrderAndChoosesTheNewOne() throws {
        let store = store()
        try store.add(saved(one))
        try store.add(saved(two))
        #expect(store.load().servers.map(\.id) == [one, two])
        #expect(store.load().chosen == two)
        try store.choose(one)
        #expect(store.load().chosenServer?.id == one)
    }

    @Test func removingChoosesAnotherAndKeepsAnEmptyList() throws {
        let store = store()
        try store.add(saved(one))
        try store.add(saved(two))
        try store.remove(two)
        #expect(store.load().chosen == one)
        try store.remove(one)
        #expect(store.load().servers.isEmpty)
        #expect(store.hasFile, "this install has run before")
    }

    @Test func aChangeLeavesTheOthersAlone() throws {
        let store = store()
        try store.add(saved(one))
        try store.add(saved(two))
        try store.update(one) { $0.signedOut = true }
        #expect(store.load()[one]?.signedOut == true)
        #expect(store.load()[two]?.signedOut == nil)
    }

    // One saved server still reads, whatever else hasn't happened yet.
    @Test func aServerFromBeforeTheListReadsAsTheList() throws {
        let store = store()
        #expect(!store.hasFile)
        try write(#"{"id":"server-one","kind":"opds","address":"http://nas.lan/opds","name":"COPS","syncsProgress":false}"#, to: store.legacyFileURL)
        #expect(store.hasFile)
        let saved = try store.read()
        #expect(saved.servers.map(\.id) == [one])
        #expect(saved.chosen == one)
        #expect(saved[one]?.customName == nil, "a file saved before names existed reads")
    }

    // Unreadable isn't "no servers", in either file (`KeychainSweep`).
    @Test func eitherFileUnreadableThrows() throws {
        let list = store()
        try write("{ not json", to: list.fileURL)
        #expect(throws: (any Error).self) { try list.read() }
        // The list says what's what, even with an old file beside it.
        try write(#"{"id":"server-one","kind":"opds","address":"http://nas.lan/opds","name":"COPS","syncsProgress":false}"#, to: list.legacyFileURL)
        #expect(throws: (any Error).self) { try list.read() }

        let legacy = store()
        try write("{ not json", to: legacy.legacyFileURL)
        #expect(throws: (any Error).self) { try legacy.read() }
    }

    // The sweep can't run while it's there, and nothing can be made of it, so
    // the next server replaces it. Otherwise each would last one launch.
    @Test func aListThatCantBeDecodedIsReplaced() throws {
        let store = store()
        try write("{ not json", to: store.fileURL)
        try store.add(saved(one))
        #expect(try store.read().servers.map(\.id) == [one])
    }

    @Test func anOldFileThatCantBeDecodedDoesntStopTheList() throws {
        let store = store()
        try write("{ not json", to: store.legacyFileURL)
        try store.add(saved(one))
        #expect(try store.read().servers.map(\.id) == [one])
    }

    @Test func aSecondServerOfTheSameNameGetsANumber() throws {
        var list = SavedServers()
        #expect(list.uniqueName("Calibre-Web") == "Calibre-Web")
        list.servers.append(saved(one, name: "Calibre-Web"))
        #expect(list.uniqueName("Calibre-Web") == "Calibre-Web 2")
        list.servers.append(saved(two, name: "Calibre-Web 2"))
        #expect(list.uniqueName("Calibre-Web") == "Calibre-Web 3")
        #expect(list.uniqueName("COPS") == "COPS")
    }

    @Test func aNameYouGaveItCountsToo() {
        var named = saved(one, name: "Calibre-Web")
        named.customName = "COPS"
        let list = SavedServers(servers: [named])
        #expect(named.displayName == "COPS")
        #expect(list.uniqueName("COPS") == "COPS 2")
    }
}

/// A file's place on the iPhone belongs to one server's copy of it.
@Suite(.temporaryFiles)
struct StorageKeyTests {
    @Test func theSameFileOnTwoServersIsTwoFiles() {
        #expect(file().storageKey(in: one) != file().storageKey(in: two))
        #expect(SourcedBook(source: one, book: book()).storageKey == file().storageKey(in: one))
    }

    // So the same file imported again opens where it was.
    @Test func importedBooksKeepThePlainName() {
        #expect(file().storageKey(in: .files) == file().storageKey)
    }

    // A catalog's IDs are URLs, and hostile ones can say anything.
    @Test func aKeyIsSafeInAPathWhateverTheFileIDIs() {
        let key = file("../../Server.json").storageKey(in: one)
        #expect(!key.contains("/"))
        #expect(key.hasPrefix("server-one."))
    }

    @Test func onlyAServersFilesGo() throws {
        let directory = folder()
        try write(to: directory.appending(path: "server-one.book-a.epub"))
        try write(to: directory.appending(path: "server-two.book-a.epub"))
        try write(to: directory.appending(path: "book-a.epub"))
        // Starts the same, but isn't this server's.
        try write(to: directory.appending(path: "server-one-more.book-a.epub"))
        StoredBookKeys.removeFiles(of: one, in: directory)
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(left == ["book-a.epub", "server-one-more.book-a.epub", "server-two.book-a.epub"])
    }

    @Test func movingKeepsWhatTheOtherAlreadyHas() throws {
        let directory = folder()
        try write("old", to: directory.appending(path: "server-one.book-a.epub"))
        try write("old", to: directory.appending(path: "server-one.book-b.epub"))
        try write("new", to: directory.appending(path: "server-two.book-b.epub"))
        StoredBookKeys.moveFiles(of: one, to: two, in: directory)
        #expect(try String(contentsOf: directory.appending(path: "server-two.book-a.epub"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: directory.appending(path: "server-two.book-b.epub"), encoding: .utf8) == "new")
    }

    @Test func storesFindABooksFileByItsServer() async throws {
        let files = try TemporaryBookFiles()
        _ = try await files.store.download(file(), in: one, from: StubLibrarySource()) { _ in }
        #expect(files.store.localFile(for: file(), in: one) != nil)
        #expect(files.store.localFile(for: file(), in: two) == nil)
        #expect(files.store.localFile(for: file(), in: .files) == nil)
        try files.store.remove(file(), in: two)
        #expect(files.store.localFile(for: file(), in: one) != nil)
    }
}

/// Carrying over an install with one server, including Adam's Duo.
@Suite(.temporaryFiles)
struct ServerStorageMigrationTests {
    let root: URL
    let migration: ServerStorageMigration
    let plain = file().storageKey
    let importedKey = file("imported").storageKey

    init() throws {
        root = folder()
        let imported = ImportedBooks(directory: root.appending(path: "Imported", directoryHint: .isDirectory))
        migration = ServerStorageMigration(
            servers: ServerStore(fileURL: root.appending(path: "Servers.json")),
            removed: RemovedServerStore(fileURL: root.appending(path: "RemovedServers.json")),
            books: StoredBookFiles(directory: root.appending(path: "Books", directoryHint: .isDirectory), imported: imported),
            positions: ReadingPositionStore(directory: root.appending(path: "ReadingPositions", directoryHint: .isDirectory)),
            bookmarks: BookmarkStore(directory: root.appending(path: "Bookmarks", directoryHint: .isDirectory)),
            onIPhone: BooksOnIPhone(fileURL: root.appending(path: "BooksOnIPhone.json"))
        )
        let incoming = root.appending(path: "incoming.epub")
        try write(to: incoming)
        try imported.add(LibraryBookDetails(book: LibraryBook(id: LibraryBookID(rawValue: "imported"), title: "Imported", files: [file("imported")])), file: incoming, cover: nil)
    }

    private func saveOldServer() throws {
        try write(#"{"id":"server-one","kind":"bookOrbit","address":"http://nas.lan","name":"BookOrbit","username":"adam","syncsProgress":true}"#, to: migration.servers.legacyFileURL)
    }

    /// A book of the old server's, and an imported one's place, as an old
    /// build left them.
    private func saveOldBooks() throws {
        let place = ReadingPosition(cfi: "epubcfi(/6/4!/4/2)", fraction: 0.3)
        try write(to: migration.books.directory.appending(path: "\(plain).epub"))
        try migration.positions.save(place, forBook: plain, needsPush: true)
        try migration.positions.save(place, forBook: importedKey)
        migration.positions.saveTrip(ReaderTrip(place: place), forBook: plain)
        try migration.bookmarks.save([], forBook: plain)
        try migration.bookmarks.save([], forBook: importedKey)
        UnsentPlaces(directory: migration.positions.directory).save([plain: SourcedBook(source: one, book: book())])
        try migration.onIPhone.record(SourcedBook(source: LibrarySourceID(rawValue: "an-older-id"), book: book()))
        try migration.onIPhone.record(SourcedBook(source: .files, book: LibraryBook(id: LibraryBookID(rawValue: "imported"), title: "Imported", files: [file("imported")])))
    }

    private func checkMoved(to id: LibrarySourceID) {
        let key = file().storageKey(in: id)
        #expect(migration.books.localFile(for: file(), in: id) != nil)
        #expect(migration.positions.progress(forBook: key)?.needsPush == true, "a place waiting to go still goes")
        #expect(migration.positions.trip(forBook: key) != nil)
        #expect(FileManager.default.fileExists(atPath: migration.bookmarks.fileURL(forBook: key).path))
        #expect(migration.positions.progress(forBook: plain) == nil)
        #expect(!FileManager.default.fileExists(atPath: migration.bookmarks.fileURL(forBook: plain).path))
        // Imported books belong to no server.
        #expect(migration.positions.progress(forBook: importedKey) != nil)
        #expect(FileManager.default.fileExists(atPath: migration.bookmarks.fileURL(forBook: importedKey).path))
    }

    @Test func aSavedServersBooksBecomeItsOwn() throws {
        try saveOldServer()
        try saveOldBooks()
        try migration.run()
        checkMoved(to: one)
        let unsent = UnsentPlaces(directory: migration.positions.directory).load()
        #expect(unsent.keys.sorted() == [file().storageKey(in: one)])
        #expect(unsent.values.first?.source == one)
        let records = migration.onIPhone.books()
        #expect(records.filter { $0.source != .files }.map(\.source) == [one], "listed under an older ID of the same server")
        #expect(records.contains { $0.source == .files })
    }

    @Test func theServerMovesToTheListAndTheOldFileGoes() throws {
        try saveOldServer()
        try migration.run()
        let saved = migration.servers.load()
        #expect(saved.servers.map(\.id) == [one])
        #expect(saved.chosen == one)
        #expect(saved[one]?.username == "adam")
        #expect(!FileManager.default.fileExists(atPath: migration.servers.legacyFileURL.path))
    }

    // A launch killed partway: the next does the rest.
    @Test func aLaunchCutShortFinishesNextTime() throws {
        try saveOldServer()
        try saveOldBooks()
        let moved = file().storageKey(in: one)
        try FileManager.default.moveItem(
            at: migration.positions.fileURL(forBook: plain), to: migration.positions.fileURL(forBook: moved)
        )
        #expect(migration.servers.load().servers.map(\.id) == [one], "reads from the old file meanwhile")
        try migration.run()
        checkMoved(to: one)
    }

    // A second run has nothing to do, and moves nothing new.
    @Test func runningAgainDoesNothing() throws {
        try saveOldServer()
        try saveOldBooks()
        try migration.run()
        // A book imported and removed since: its plain place isn't a server's.
        try migration.positions.save(ReadingPosition(fraction: 0.1), forBook: file("removed").storageKey)
        try migration.run()
        #expect(migration.positions.progress(forBook: file("removed").storageKey) != nil)
    }

    // Saved already by a launch that couldn't run this: the list stays.
    @Test func aListAlreadySavedStays() throws {
        try saveOldServer()
        try migration.servers.save(SavedServers(servers: [SavedServer(id: one, kind: .bookOrbit, address: "http://nas.lan", name: "BookOrbit", signedOut: true)], chosen: one))
        try migration.run()
        #expect(migration.servers.load()[one]?.signedOut == true)
        #expect(!FileManager.default.fileExists(atPath: migration.servers.legacyFileURL.path))
    }

    // The old file can't be read: nothing moves, and it stays to try again.
    @Test func anUnreadableServerMovesNothing() throws {
        try write("{ not json", to: migration.servers.legacyFileURL)
        try saveOldBooks()
        #expect(throws: (any Error).self) { try migration.run() }
        #expect(migration.positions.progress(forBook: plain) != nil)
        #expect(FileManager.default.fileExists(atPath: migration.servers.legacyFileURL.path))
    }

    // Unreadable, with a list started since: it goes, or it fails every launch.
    @Test func anUnreadableOldFileGoesOnceThereIsAList() throws {
        try write("{ not json", to: migration.servers.legacyFileURL)
        try migration.servers.add(SavedServer(id: two, kind: .bookOrbit, address: "http://nas.lan", name: "BookOrbit"))
        try migration.run()
        #expect(!FileManager.default.fileExists(atPath: migration.servers.legacyFileURL.path))
        #expect(migration.servers.load().servers.map(\.id) == [two])
    }

    // A server added before this could run keeps its own books.
    @Test func anotherServersRecordsStayItsOwn() throws {
        try saveOldServer()
        try migration.servers.save(SavedServers(servers: [
            SavedServer(id: one, kind: .bookOrbit, address: "http://nas.lan", name: "BookOrbit"),
            SavedServer(id: two, kind: .opds, address: "http://two.lan/opds", name: "COPS"),
        ], chosen: two))
        let theirs = SourcedBook(source: two, book: book("9", "Theirs"))
        try migration.onIPhone.record(theirs)
        try migration.run()
        #expect(migration.onIPhone.books().contains(theirs))
    }

    // Cut short, the next launch carries on under the same ID.
    @Test func aRemovedServersMoveCutShortKeepsItsID() throws {
        try saveOldBooks()
        try write(#"{"identity":"bookOrbit|http://nas.lan|adam"}"#, to: migration.removed.legacyFileURL)
        let id = LibrarySourceID(rawValue: "removed-earlier")
        try migration.removed.add(RemovedServer(identity: "bookOrbit|http://nas.lan|adam", id: id))
        try FileManager.default.moveItem(
            at: migration.positions.fileURL(forBook: plain), to: migration.positions.fileURL(forBook: file().storageKey(in: id))
        )
        try migration.run()
        #expect(migration.removed.load().map(\.id) == [id])
        checkMoved(to: id)
    }

    // Removed with its books kept: they wait for it, as they did.
    @Test func aRemovedServersKeptBooksStayItsOwn() throws {
        try saveOldBooks()
        try write(#"{"identity":"bookOrbit|http://nas.lan|adam"}"#, to: migration.removed.legacyFileURL)
        try migration.run()
        let removed = migration.removed.load()
        #expect(removed.map(\.identity) == ["bookOrbit|http://nas.lan|adam"])
        checkMoved(to: try #require(removed.first?.id))
        #expect(!migration.removed.hasLegacyFile)
        #expect(migration.servers.load().servers.isEmpty)
        // Only once.
        try migration.run()
        #expect(migration.removed.load() == removed)
    }

    // A new install: nothing to do, and no list until a server is added, so
    // the reinstall wipe still sees a new install.
    @Test func aNewInstallIsLeftAlone() throws {
        try saveOldBooks()
        try migration.run()
        #expect(migration.positions.progress(forBook: plain) != nil)
        #expect(!migration.servers.hasFile)
    }
}

/// The launch sweep with several servers (`docs/notes/network-trust.md`).
@Suite(.serialized, .temporaryFiles)
struct SeveralServersKeychainTests {
    private func saved(_ id: String, signedOut: Bool? = nil) -> SavedServer {
        SavedServer(id: LibrarySourceID(rawValue: id), kind: .opds, address: "http://\(UUID().uuidString.lowercased()).lan/opds", name: "COPS", signedOut: signedOut)
    }

    private func signIn(_ id: String) async throws {
        try await KeychainPasswordStore(serverID: id).save(PasswordCredentials(username: "u", password: "p"))
        try await KeychainBookOrbitTokenStore(serverID: id).save(BookOrbitCredentials(accessToken: "a"))
        try KeychainCertificatePinStore(serverID: id).save(CertificatePin(sha256: Data(repeating: 1, count: 32)))
        try KeychainCatalogSecretStore(serverID: id).save(OPDSURLSecret("0123456789abcdef"))
    }

    private func hasSignIn(_ id: String) async throws -> Bool {
        let password = try await KeychainPasswordStore(serverID: id).load()
        let tokens = try await KeychainBookOrbitTokenStore(serverID: id).load()
        return password != nil && tokens != nil
    }

    private func hasPin(_ id: String) throws -> Bool {
        try KeychainCertificatePinStore(serverID: id).load() != nil
    }

    @Test func theSweepKeepsEverySavedServerAndNothingElse() async throws {
        let prefix = "sweep-several-\(UUID().uuidString)-"
        let (a, b, gone) = (prefix + "a", prefix + "b", prefix + "gone")
        defer { for id in [a, b, gone] { try? ServerCredentials.removeAll(serverID: id) } }
        for id in [a, b, gone] { try await signIn(id) }
        let store = ServerStore(fileURL: folder().appending(path: "Servers.json"))
        try store.save(SavedServers(servers: [saved(a), saved(b)]))

        try KeychainSweep.run(servers: store) { $0.hasPrefix(prefix) }

        #expect(try await hasSignIn(a))
        #expect(try await hasSignIn(b))
        #expect(try await !hasSignIn(gone))
        #expect(try !hasPin(gone))
    }

    @Test func onlyTheServerSignedOutOfLosesItsSignIn() async throws {
        let prefix = "sweep-several-\(UUID().uuidString)-"
        let (a, b) = (prefix + "a", prefix + "b")
        defer { for id in [a, b] { try? ServerCredentials.removeAll(serverID: id) } }
        for id in [a, b] { try await signIn(id) }
        let store = ServerStore(fileURL: folder().appending(path: "Servers.json"))
        try store.save(SavedServers(servers: [saved(a, signedOut: true), saved(b)]))

        try KeychainSweep.run(servers: store) { $0.hasPrefix(prefix) }

        #expect(try await !hasSignIn(a))
        #expect(try hasPin(a), "its certificate stays with the server")
        #expect(try await hasSignIn(b))
    }

    // Before the list moves: the old file's server is the one to keep.
    @Test func aServerInTheOldFileIsKept() async throws {
        let prefix = "sweep-several-\(UUID().uuidString)-"
        let (a, gone) = (prefix + "a", prefix + "gone")
        defer { for id in [a, gone] { try? ServerCredentials.removeAll(serverID: id) } }
        for id in [a, gone] { try await signIn(id) }
        let store = ServerStore(fileURL: folder().appending(path: "Servers.json"))
        try write(#"{"id":"\#(a)","kind":"bookOrbit","address":"http://nas.lan","name":"BookOrbit","syncsProgress":true}"#, to: store.legacyFileURL)

        try KeychainSweep.run(servers: store) { $0.hasPrefix(prefix) }

        #expect(try await hasSignIn(a))
        #expect(try await !hasSignIn(gone))
    }

    @Test func theSweepDeletesNothingIfTheListCantBeRead() async throws {
        let prefix = "sweep-several-\(UUID().uuidString)-"
        let a = prefix + "a"
        defer { try? ServerCredentials.removeAll(serverID: a) }
        try await signIn(a)
        let store = ServerStore(fileURL: folder().appending(path: "Servers.json"))
        try write("{ not json", to: store.fileURL)
        #expect(throws: (any Error).self) { try KeychainSweep.run(servers: store) { $0.hasPrefix(prefix) } }
        #expect(try await hasSignIn(a))
    }

    @Test func removingAServerRemovesOnlyItsSecrets() async throws {
        let prefix = "sweep-several-\(UUID().uuidString)-"
        let (a, b) = (prefix + "a", prefix + "b")
        defer { for id in [a, b] { try? ServerCredentials.removeAll(serverID: id) } }
        for id in [a, b] { try await signIn(id) }
        try ServerCredentials.removeAll(serverID: a)
        #expect(try await !hasSignIn(a))
        #expect(try !hasPin(a))
        #expect(try await hasSignIn(b))
        #expect(try hasPin(b))
    }

    /// Comparing a catalog with a key puts the key back, here on the iPhone.
    @Test func aCatalogsKeyIsComparedAsItReallyIs() throws {
        let id = "isat-\(UUID().uuidString)"
        defer { try? ServerCredentials.removeAll(serverID: id) }
        let key = "0123456789abcdef0123456789abcdef"
        let address = try #require(URL(string: "https://kavita.example.com/api/opds/\(key)"))
        let secret = try #require(OPDSURLSecret.detect(in: address))
        try KeychainCatalogSecretStore(serverID: id).save(secret)
        let saved = SavedServer(id: LibrarySourceID(rawValue: id), kind: .opds, address: secret.redact(address.absoluteString), name: "Kavita")
        #expect(saved.isAt(address, username: nil))
        let other = try #require(URL(string: "https://kavita.example.com/api/opds/fedcba9876543210fedcba9876543210"))
        #expect(!saved.isAt(other, username: nil))
    }
}

@MainActor
@Suite(.temporaryFiles)
struct SeveralServersOpenerTests {
    let files: TemporaryBookFiles
    let opener: BookOpener

    init() throws {
        files = try TemporaryBookFiles()
        opener = BookOpener(files: files.store)
    }

    @Test func aDownloadIsOneServersBook() async {
        let first = SourcedBook(source: one, book: book())
        let second = SourcedBook(source: two, book: book())
        opener.download(first, from: StubLibrarySource())
        #expect(opener.status(of: second) == .notDownloaded)
        #expect(await eventually { opener.status(of: first) == .downloaded })
        #expect(opener.status(of: second) == .notDownloaded)
        opener.removeDownload(second)
        #expect(opener.status(of: first) == .downloaded)
    }

    @Test func removingAServerStopsOnlyItsDownloads() async throws {
        let slow = StubLibrarySource(downloadTime: .milliseconds(300))
        let first = SourcedBook(source: one, book: book())
        let second = SourcedBook(source: two, book: book())
        opener.download(first, from: slow)
        opener.download(second, from: slow)
        opener.cancelAll(in: one)
        #expect(opener.status(of: first) == .notDownloaded)
        #expect(await eventually { opener.status(of: second) == .downloaded })
        try await Task.sleep(for: .milliseconds(100))
        #expect(opener.status(of: first) == .notDownloaded)
    }

    @Test func theReaderKeepsItsPlaceUnderTheServer() {
        let opened = OpenedBook(book: book(), source: one, file: file(), url: URL(filePath: "/a.epub"))
        #expect(opened.reader.id == file().storageKey(in: one))
    }
}

@MainActor
@Suite(.temporaryFiles)
struct SeveralServersLibraryTests {
    private func library(_ a: StubLibrarySource = StubLibrarySource(), _ b: StubLibrarySource = StubLibrarySource()) async -> LibraryModel {
        let model = LibraryModel(
            recents: RecentBooks(fileURL: folder().appending(path: "RecentBooks.json")),
            finished: FinishedBooks(fileURL: folder().appending(path: "FinishedBooks.json")),
            onIPhone: BooksOnIPhone(fileURL: folder().appending(path: "BooksOnIPhone.json")), imported: .temporary()
        )
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: a))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: b))
        return model
    }

    @Test func theLibraryShowsTheChosenServer() async {
        let model = await library()
        #expect(model.server?.id == two, "the last added")
        model.choose(one)
        #expect(model.server?.id == one)
        model.choose(LibrarySourceID(rawValue: "not-a-server"))
        #expect(model.server?.id == one)
    }

    @Test func eachBookGoesToItsOwnServer() async {
        let model = await library()
        #expect(model.source(for: one) != nil)
        #expect(model.source(for: LibrarySourceID(rawValue: "not-a-server")) == nil)
        #expect(model.server(one)?.name == "BookOrbit")
        #expect(model.server(two)?.name == "Calibre-Web")
    }

    @Test func booksNameTheirServerOnlyWithSeveral() async {
        let model = await library()
        #expect(model.label(for: SourcedBook(source: one, book: book())) == "BookOrbit")
        #expect(model.label(for: SourcedBook(source: .files, book: book())) == nil, "an imported book has none")
        model.remove(two)
        #expect(model.label(for: SourcedBook(source: one, book: book())) == nil)
    }

    @Test func aProblemIsOneServers() async {
        let model = await library()
        model.report(URLError(.cannotConnectToHost), server: one)
        #expect(model.connection(one)?.problem == .unreachable(server: "BookOrbit"))
        #expect(model.connection(two)?.problem == nil)
    }

    // A server at home would nag every time you're out (decision 36).
    @Test func homeShowsOnlyASignInWithSeveral() async {
        let model = await library()
        model.report(URLError(.cannotConnectToHost), server: one)
        #expect(model.homeProblems.isEmpty)
        model.report(LibraryError.signedOut, server: two)
        #expect(model.homeProblems.map(\.server) == [two])
        model.report(LibraryError.signedOut, server: one)
        #expect(model.homeProblems.map(\.server) == [one, two], "one banner per server")
        model.remove(two)
        model.report(URLError(.cannotConnectToHost), server: one)
        #expect(model.homeProblems.map(\.server) == [one], "with one, as before")
    }

    @Test func aNameYouGiveReachesItsBanner() async {
        let model = await library()
        model.report(LibraryError.signedOut, server: one)
        model.rename(one, to: "Home")
        #expect(model.server(one)?.name == "Home")
        #expect(model.connection(one)?.problem == .signedOut(server: "Home"))
    }

    // A server's late answers go nowhere once it's removed.
    @Test func removingLeavesTheOtherAndItsLists() async {
        let model = await library()
        let kept = model.feed(LibraryLink(rawValue: "a"), from: two)
        let gone = model.feed(LibraryLink(rawValue: "a"), from: one)
        #expect(kept !== gone, "the same link on two servers is two lists")
        model.choose(one)
        model.remove(one)
        #expect(model.server?.id == two)
        #expect(model.feed(LibraryLink(rawValue: "a"), from: two) === kept)
        #expect(model.feed(LibraryLink(rawValue: "a"), from: one) == nil)
    }

    @Test func removingTheLastLeavesNone() async {
        let model = await library()
        model.disconnect()
        #expect(model.server == nil)
        #expect(model.connections.isEmpty)
    }
}

/// A server that answers its Continue reading and search from a fixed list.
private nonisolated final class ListSource: LibrarySource, Sendable {
    let books: [LibraryBook]
    let support: LibrarySearchSupport
    let delay: Duration
    let error: (any Error & Sendable)?

    init(_ books: [LibraryBook] = [], support: LibrarySearchSupport = .books, delay: Duration = .zero, error: (any Error & Sendable)? = nil) {
        self.books = books
        self.support = support
        self.delay = delay
        self.error = error
    }

    func root() async throws -> LibraryRoot {
        LibraryRoot(chips: [], search: support, continueReading: LibraryLink(rawValue: "reading"))
    }

    func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        if let error { throw error }
        return LibraryFeed(books: books)
    }

    func search(_ query: String) async throws -> LibrarySearchResults {
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
        return LibrarySearchResults(query: query, books: LibraryFeed(books: books))
    }

    func details(for book: LibraryBook) async throws -> LibraryBookDetails { LibraryBookDetails(book: book) }
    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data { throw LibraryError.notFound }
    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw LibraryError.notFound
    }
}

@MainActor
@Suite(.temporaryFiles)
struct SeveralServersHomeAndSearchTests {
    private func library() -> LibraryModel {
        LibraryModel(
            recents: RecentBooks(fileURL: folder().appending(path: "RecentBooks.json")),
            finished: FinishedBooks(fileURL: folder().appending(path: "FinishedBooks.json")),
            onIPhone: BooksOnIPhone(fileURL: folder().appending(path: "BooksOnIPhone.json")), imported: .temporary()
        )
    }

    private func search(_ library: LibraryModel, downloaded: @escaping (SourcedBook) -> Bool = { _ in false }) -> SearchModel {
        SearchModel(library: library, isOnIPhone: downloaded, defaults: UserDefaults.testSuite("SeveralServersSearch"), pause: .zero)
    }

    @Test func homeHoldsEveryServersBooks() async {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource([book("1", "One")])))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource([book("1", "Also one")])))
        #expect(Set(model.continueReading.map(\.id)) == [
            SourcedBook.ID(source: one, book: LibraryBookID(rawValue: "1")),
            SourcedBook.ID(source: two, book: LibraryBookID(rawValue: "1")),
        ], "the same number on two servers shows twice")
    }

    @Test func removingAServerTakesItsBooksOffHome() async {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource([book("1", "One")])))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource([book("2", "Two")])))
        model.remove(one)
        #expect(model.continueReading.map(\.book.title) == ["Two"])
    }

    @Test func oneServerFailingLeavesTheOthersBooks() async {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource([book("1", "One")])))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource(error: URLError(.cannotConnectToHost))))
        #expect(model.continueReading.map(\.book.title) == ["One"])
        #expect(!model.continueReadingFailed, "only when none answered")
        #expect(model.homeLoaded)
    }

    @Test func searchCoversEveryServerInOrder() async {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource([book("1", "Moby-Dick")])))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource([book("1", "Moby-Dick")])))
        let search = search(model)
        search.query = "moby"
        await search.waitForSearch()
        #expect(search.sections.map(\.source) == [one, two])
        #expect(search.sections.allSatisfy { $0.results?.books.count == 1 && $0.state == .loaded })
        #expect(search.state == .loaded)
    }

    // A slow server fills in later, and doesn't hold up or move the rest.
    @Test func aSlowServerFillsInItsOwnSection() async throws {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource([book("1", "Moby-Dick")], delay: .milliseconds(400))))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource([book("2", "Moby-Dick")])))
        let search = search(model)
        search.query = "moby"
        #expect(await eventually { search.sections.last?.results != nil })
        #expect(search.sections.map(\.source) == [one, two])
        #expect(search.sections.first?.state == .searching)
        #expect(search.state == .searching)
        await search.waitForSearch()
        #expect(search.sections.first?.results?.books.count == 1)
        #expect(search.state == .loaded)
    }

    @Test func aServerThatCantBeReachedDoesntStopTheOthers() async {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource(error: URLError(.cannotConnectToHost))))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource([book("2", "Moby-Dick")])))
        let search = search(model)
        search.query = "moby"
        await search.waitForSearch()
        #expect(model.connection(one)?.problem == .unreachable(server: "BookOrbit"))
        #expect(search.sections.first?.state == .loaded, "the problem says why")
        #expect(search.sections.last?.results?.books.count == 1)
    }

    @Test func aCatalogWithoutSearchSaysSoAndKeepsItsDownloads() async {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource([book("1", "Moby-Dick")])))
        let source = ListSource([book("2", "Never listed")], support: .unavailable)
        await model.connect(LibraryServer(id: two, name: "COPS", source: source))
        try? model.onIPhone.record(SourcedBook(source: two, book: book("3", "Moby-Dick")))
        let search = search(model) { $0.source == two }
        search.query = "moby"
        await search.waitForSearch()
        #expect(search.sections.last?.source == two)
        #expect(search.sections.last?.results?.books.map(\.book.title) == ["Moby-Dick"])
    }

    @Test func importedBooksComeLastWithSeveral() async throws {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource()))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource()))
        let imported = SourcedBook(source: .files, book: book("i", "Moby-Dick"))
        try model.onIPhone.record(imported)
        let incoming = folder().appending(path: "a.epub")
        try write(to: incoming)
        try model.imported.add(LibraryBookDetails(book: imported.book), file: incoming, cover: nil)
        model.importedChanged()
        let search = search(model) { _ in true }
        search.query = "moby"
        await search.waitForSearch()
        #expect(search.sections.map(\.source) == [one, two, .files])
    }

    // Each section stays short, and links to the rest of its own.
    @Test func eachSectionShowsThreeAndAllItsBooks() async {
        let model = library()
        let many = (1...5).map { book("\($0)", "Moby \($0)") }
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource(many)))
        await model.connect(LibraryServer(id: two, name: "Calibre-Web", source: ListSource(many)))
        let search = search(model)
        #expect(search.bookLimit == SearchModel.sectionBookLimit)
        model.remove(two)
        #expect(search.bookLimit == SearchModel.bookLimit, "with one, as before")
    }

    @Test func withOneServerImportedBooksStayAmongItsOwn() async throws {
        let model = library()
        await model.connect(LibraryServer(id: one, name: "BookOrbit", source: ListSource()))
        let imported = SourcedBook(source: .files, book: book("i", "Moby-Dick"))
        try model.onIPhone.record(imported)
        let search = search(model) { _ in true }
        search.query = "moby"
        await search.waitForSearch()
        #expect(search.sections.map(\.source) == [one])
        #expect(search.results?.books == [imported])
    }
}

/// Adding, naming and removing, through the shell.
@MainActor
@Suite(.temporaryFiles)
struct SeveralServersShellTests {
    let files: TemporaryBookFiles
    let model: ShellModel
    let first = SavedServer(id: SavedServer.newID(), kind: .opds, address: "http://one.lan/opds", name: "Calibre-Web")
    let second = SavedServer(id: SavedServer.newID(), kind: .opds, address: "http://two.lan/opds", name: "Calibre-Web")

    init() throws {
        files = try TemporaryBookFiles()
        model = makeShell(opener: BookOpener(files: files.store))
    }

    @Test func theFirstOpensHomeAnotherItsLibrary() {
        model.setup.finished(first)
        #expect(model.tab == .home)
        model.openSettings()
        model.push(.setup(.choose))
        model.setup.finished(second)
        #expect(model.tab == .library)
        #expect(model.library.server?.id == second.id)
        #expect(model[path: .home].routes.isEmpty)
        #expect(model[path: .library].routes.isEmpty)
    }

    @Test func aSecondOfTheSameNameGetsANumber() {
        model.setup.finished(first)
        model.setup.finished(second)
        #expect(model.library.server(first.id)?.name == "Calibre-Web")
        #expect(model.library.server(second.id)?.name == "Calibre-Web 2")
        #expect(model.servers.load()[second.id]?.name == "Calibre-Web 2")
    }

    @Test func theNameIsYoursOrItsOwn() {
        model.setup.finished(first)
        model.rename(first.id, to: "  Home  ")
        #expect(model.library.server(first.id)?.name == "Home")
        #expect(model.servers.load()[first.id]?.customName == "Home")
        #expect(model.servers.load()[first.id]?.name == "Calibre-Web")
        model.rename(first.id, to: "")
        #expect(model.library.server(first.id)?.name == "Calibre-Web")
        #expect(model.servers.load()[first.id]?.customName == nil)
    }

    @Test func chosenIsRemembered() {
        model.setup.finished(first)
        model.setup.finished(second)
        model.chooseServer(first.id)
        #expect(model.library.server?.id == first.id)
        #expect(model.servers.load().chosen == first.id)
    }

    private func emptyList(on server: SavedServer) -> ShellRoute {
        .feed(LibraryEntry(kind: .feed, title: "Keep Reading", link: LibraryLink(rawValue: "keep")), from: server.id)
    }

    // An empty list's button, on a list Search opened from the other server:
    // the Library shows that list's server, and Search stays where it was.
    @Test func openLibraryShowsTheListsServer() {
        model.setup.finished(first)
        model.setup.finished(second)
        model.push(emptyList(on: second))
        model.select(.search)
        model.push(emptyList(on: first))

        model.openLibrary(showing: first.id)

        #expect(model.tab == .library)
        #expect(model.library.server?.id == first.id)
        #expect(model.servers.load().chosen == first.id)
        #expect(model[path: .library].routes.isEmpty)
        #expect(model[path: .search].routes == [emptyList(on: first)])
    }

    @Test func openLibraryGoesToTheTop() {
        model.setup.finished(first)
        model.setup.finished(second)
        model.push(emptyList(on: second))

        model.openLibrary(showing: second.id)

        #expect(model.tab == .library)
        #expect(model.library.server?.id == second.id)
        #expect(model[path: .library].routes.isEmpty)
    }

    // An imported book's author can open a list, and Files is no server.
    @Test func openLibraryKeepsTheServerForAListFromFiles() {
        model.setup.finished(first)
        model.setup.finished(second)

        model.openLibrary(showing: .files)

        #expect(model.library.server?.id == second.id)
        #expect(model.servers.load().chosen == second.id)
    }

    @Test func removingOneLeavesTheOther() async throws {
        model.setup.finished(first)
        model.setup.finished(second)
        let kept = SourcedBook(source: second.id, book: book())
        let gone = SourcedBook(source: first.id, book: book())
        for book in [kept, gone] {
            let bookFile = try #require(book.book.readableFile)
            try write(to: #require(files.store.url(for: bookFile, in: book.source)))
            try model.library.onIPhone.record(book)
            try model.library.recents.record(book)
            try model.library.finished.set(true, for: book.id)
            try model.places.store.save(ReadingPosition(fraction: 0.3), forBook: #require(book.storageKey))
        }
        model.select(.library)
        model.push(.cover(gone))
        model.push(.cover(kept))
        model.select(.home)
        model.lastSpread = .duoUnfolded
        model.openSettings()
        model.push(.settingsPage(.server(first.id)))

        await model.removeServer(first.id, removingBooks: true)

        #expect(model.servers.load().servers.map(\.id) == [second.id])
        #expect(model.library.server?.id == second.id)
        #expect(model.opener.localFile(for: gone) == nil)
        #expect(model.opener.localFile(for: kept) != nil)
        #expect(model.library.recents.records().map(\.book.id) == [kept.id])
        #expect(!model.library.finished.contains(gone.id))
        #expect(model.library.finished.contains(kept.id))
        #expect(model.library.onIPhone.books().map(\.id) == [kept.id])
        #expect(model.places.store.progress(forBook: kept.storageKey ?? "") != nil)
        #expect(model[path: .library].routes == [.cover(kept)], "only what showed its books closes")
        #expect(model[path: .home].routes == [.settings])
        #expect(!model.needsSetup)
    }

    // Downloaded from a list entry without its files, so no record names it.
    @Test func removeBooksTooLeavesNoFileOfTheServers() async throws {
        model.setup.finished(first)
        model.setup.finished(second)
        let books = files.store.directory
        try write(to: books.appending(path: file("unnamed").storageKey(in: first.id) + ".epub"))
        try write(to: books.appending(path: file("unnamed").storageKey(in: second.id) + ".epub"))
        await model.removeServer(first.id, removingBooks: true)
        let left = try FileManager.default.contentsOfDirectory(atPath: books.path)
        #expect(left == [file("unnamed").storageKey(in: second.id) + ".epub"])
    }

    @Test func keepingBooksLeavesThemAll() async throws {
        model.setup.finished(first)
        let name = file("unnamed").storageKey(in: first.id) + ".epub"
        try write(to: files.store.directory.appending(path: name))
        await model.removeServer(first.id, removingBooks: false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.store.directory.path) == [name])
    }

    // Another account is another server: this one's unsent places and
    // bookmarks would go to it.
    @Test func signingInAgainIsForTheSameAccount() async throws {
        var withAccount = first
        withAccount.username = "adam"
        model.setup.finished(withAccount)
        await #expect(throws: LibraryError.self) {
            try await model.signInAgain(first.id, username: "sam", password: "secret")
        }
        #expect(model.servers.load()[first.id]?.username == "adam")
        #expect(model.library.server(first.id)?.username == "adam")
    }

    // A failed save isn't a server added: it'd be gone next launch, and its
    // kept books with it.
    @Test func booksComeBackOnlyOnceTheServerIsSaved() async throws {
        model.setup.finished(first)
        let kept = SourcedBook(source: first.id, book: book())
        let bookFile = try #require(kept.book.readableFile)
        try write(to: #require(files.store.url(for: bookFile, in: kept.source)))
        try model.library.onIPhone.record(kept)
        await model.removeServer(first.id, removingBooks: false)
        // A folder where the list goes: it can't be written.
        try FileManager.default.removeItem(at: model.servers.fileURL)
        try FileManager.default.createDirectory(at: model.servers.fileURL, withIntermediateDirectories: true)

        let back = SavedServer(id: SavedServer.newID(), kind: .opds, address: first.address, name: "Calibre-Web")
        model.setup.finished(back)

        #expect(model.library.server(back.id) != nil, "usable for now")
        #expect(model.opener.localFile(for: kept) != nil, "still waiting under its old ID")
        #expect(model.removedServers.load().map(\.id) == [first.id])
    }

    @Test func removingTheLastIsAsItWas() async {
        model.setup.finished(first)
        await model.removeServer(first.id, removingBooks: false)
        #expect(model.needsSetup)
        #expect(model.servers.load().servers.isEmpty)
    }

    // Kept books wait for their own server, not for just any.
    @Test func aRemovedServersBooksWaitForIt() async throws {
        model.setup.finished(first)
        let kept = SourcedBook(source: first.id, book: book())
        let bookFile = try #require(kept.book.readableFile)
        try write(to: #require(files.store.url(for: bookFile, in: kept.source)))
        try model.library.onIPhone.record(kept)
        await model.removeServer(first.id, removingBooks: false)
        #expect(model.removedServers.load().map(\.id) == [first.id])

        // Another one comes and goes, and they're still there.
        model.setup.finished(second)
        #expect(model.opener.localFile(for: SourcedBook(source: second.id, book: book())) == nil)
        #expect(model.opener.localFile(for: kept) != nil)
        await model.removeServer(second.id, removingBooks: false)
        #expect(model.removedServers.load().count == 2)

        let back = SavedServer(id: SavedServer.newID(), kind: .opds, address: first.address, name: "Calibre-Web")
        model.setup.finished(back)
        #expect(model.opener.localFile(for: SourcedBook(source: back.id, book: book())) != nil)
        #expect(model.library.onIPhone.books().map(\.source) == [back.id])
        #expect(model.removedServers.load().map(\.id) == [second.id])
    }

    @Test func aCatalogWithAKeyLeavesNothingToComeBackTo() async throws {
        let id = SavedServer.newID()
        await model.library.connect(LibraryServer(
            id: id, name: "Kavita",
            origin: LibraryServer.origin(kind: .opds, address: "https://k.example.com/api/opds/{key}", secret: OPDSURLSecret("0123456789abcdef")),
            source: StubLibrarySource()
        ))
        let place = try #require(SourcedBook(source: id, book: book()).storageKey)
        try model.places.store.save(ReadingPosition(fraction: 0.3), forBook: place)
        await model.removeServer(id, removingBooks: false)
        #expect(model.removedServers.load().isEmpty)
        #expect(model.places.store.progress(forBook: place) == nil)
    }

    // A place goes to its own server, whichever is shown.
    @Test func aBookSyncsWithItsOwnServer() async {
        let client = BookOrbitClient(baseURL: URL(string: "http://localhost:3300")!)
        let bookOrbit = LibraryServer(id: one, name: "BookOrbit", source: BookOrbitSource(client: client), syncsProgress: true)
        await model.library.connect(bookOrbit)
        await model.library.connect(LibraryServer(id: two, name: "Calibre-Web", source: StubLibrarySource()))
        let numbered = LibraryBook(id: LibraryBookID(rawValue: "3"), title: "Moby-Dick", files: [LibraryFile(id: LibraryFileID(rawValue: "3"), format: "epub", isPrimary: true)])
        #expect(ShellModel.progressSync(for: SourcedBook(source: one, book: numbered), on: model.library.server(one)) != nil)
        #expect(ShellModel.progressSync(for: SourcedBook(source: two, book: numbered), on: model.library.server(two)) == nil)
        #expect(ShellModel.progressSync(for: SourcedBook(source: two, book: numbered), on: model.library.server(one)) == nil, "never another server's")
    }
}

/// Telling the same server twice, in setup (decision 36).
@MainActor
@Suite(.temporaryFiles)
struct SeveralServersSetupTests {
    private func setup(_ saved: [SavedServer]) -> (SetupModel, Finished) {
        let setup = SetupModel()
        let finished = Finished()
        setup.saved = { saved }
        setup.finished = { finished.servers.append($0) }
        return (setup, finished)
    }

    final class Finished {
        var servers: [SavedServer] = []
    }

    private let bookOrbit = SavedServer(id: SavedServer.newID(), kind: .bookOrbit, address: "http://nas.lan:3300", name: "BookOrbit", username: "adam")
    private let catalog = SavedServer(id: SavedServer.newID(), kind: .opds, address: "http://nas.lan:8083/opds", name: "Calibre-Web")

    // Said before the password is sent anywhere.
    @Test func theSameBookOrbitAndAccountSaysSoAtOnce() {
        let (setup, _) = setup([bookOrbit])
        setup.bookOrbitAddress = "http://nas.lan:3300"
        setup.bookOrbitUsername = "adam"
        setup.bookOrbitPassword = "secret"
        setup.signInToBookOrbit()
        #expect(setup.error == "You’ve already added this server.")
        #expect(!setup.working)
    }

    @Test func anotherAccountOnTheSameServerIsAnotherServer() {
        let (setup, _) = setup([bookOrbit])
        setup.bookOrbitAddress = "http://nas.lan:3300"
        setup.bookOrbitUsername = "sam"
        setup.bookOrbitPassword = "secret"
        setup.signInToBookOrbit()
        #expect(setup.error == nil)
        setup.leftStep()
    }

    @Test func aCatalogAndABookOrbitAtOneAddressAreDifferent() {
        #expect(bookOrbit.isAt(URL(string: "http://nas.lan:3300")!, username: "adam"))
        #expect(!catalog.isAt(URL(string: "http://nas.lan:8083/opds")!, username: "adam"))
        #expect(catalog.isAt(URL(string: "http://nas.lan:8083/opds")!, username: nil))
        #expect(catalog.isAt(URL(string: "http://nas.lan:8083/opds")!, username: ""))
    }

    // It's the catalog's say: one line, and no longer than a name needs.
    @Test func aCatalogsOwnNameIsTidied() throws {
        let url = try #require(URL(string: "http://nas.lan/opds"))
        #expect(SetupModel.name(" Calibre-Web ", url: url) == "Calibre-Web")
        #expect(SetupModel.name("Two\nLines\u{202E}", url: url).contains("\n") == false)
        #expect(SetupModel.name(String(repeating: "a", count: 500), url: url).count == 60)
        #expect(SetupModel.name("\n ", url: url) == "nas.lan")
        #expect(SetupModel.name(nil, url: url) == "nas.lan")
    }

    @Test func aNameTypedGoesWithTheServer() async {
        let (setup, finished) = setup([])
        setup.catalogAddress = "http://nas.lan:8083/opds"
        setup.catalogName = "  Home library "
        #expect(setup.catalogName == "  Home library ")
        setup.reset()
        #expect(setup.catalogName.isEmpty, "setup starts clean")
        #expect(finished.servers.isEmpty)
    }
}
