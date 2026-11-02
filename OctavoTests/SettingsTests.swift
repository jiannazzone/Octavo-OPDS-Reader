import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Settings (step 14): its pages folded and unfolded, Remove server, the
/// books on the iPhone and the licences.
@MainActor
@Suite(.temporaryFiles)
struct SettingsNavigationTests {
    // Folded, a row's page slides in over the list, and Back returns to it.
    @Test func foldedAPageGoesOverTheList() {
        let model = makeShell()
        model.openSettings()
        model.openSettingsPage(.storage, twoPages: false)
        #expect(model[path: .home].routes == [.settings, .settingsPage(.storage)])
        #expect(model[path: .home].lastMove == .push)
        model.back(.home, twoPages: false)
        #expect(model[path: .home].routes == [.settings])
    }

    // Unfolded, the list stays and the right page changes without a slide.
    @Test func unfoldedAPageReplacesTheOneBesideTheList() {
        let model = makeShell()
        model.openSettings()
        model.openSettingsPage(.storage, twoPages: true)
        #expect(model[path: .home].routes == [.settings, .settingsPage(.storage)])
        #expect(model[path: .home].lastMove == .replace)
        model.openSettingsPage(.licences, twoPages: true)
        #expect(model[path: .home].routes == [.settings, .settingsPage(.licences)])
        #expect(model[path: .home].lastMove == .replace)
    }

    // Unfolded, the list and its page are one screen: Back leaves both.
    @Test func unfoldedBackLeavesSettings() {
        let model = makeShell()
        model.openSettings()
        model.openSettingsPage(.server, twoPages: true)
        model.back(.home, twoPages: true)
        #expect(model[path: .home].routes.isEmpty)
        #expect(model[path: .home].lastMove == .pop)
    }

    // A screen opened from a page (Sign in again) goes back to the page.
    @Test func backFromAScreenOverAPageIsOneStep() {
        let model = makeShell()
        model.openSettings()
        model.openSettingsPage(.server, twoPages: true)
        model.push(.signInAgain)
        model.back(.home, twoPages: true)
        #expect(model[path: .home].routes == [.settings, .settingsPage(.server)])
    }

    // Only Settings' list takes a page beside it.
    @Test func aPageNeedsTheList() {
        let model = makeShell()
        model.openSettingsPage(.storage, twoPages: true)
        #expect(model[path: .home].routes.isEmpty)
    }
}

/// Remove server (decision 24): what goes, what stays.
@MainActor
@Suite(.temporaryFiles)
struct RemoveServerTests {
    static let server = LibrarySourceID(rawValue: "server-remove-test")
    let files: TemporaryBookFiles
    let model: ShellModel
    let downloaded: SourcedBook
    let imported: SourcedBook

    init() async throws {
        files = try TemporaryBookFiles()
        model = makeShell(opener: BookOpener(files: files.store))
        let file = { (id: String) in LibraryFile(id: LibraryFileID(rawValue: id), format: "epub", isPrimary: true) }
        downloaded = SourcedBook(source: Self.server, book: LibraryBook(
            id: LibraryBookID(rawValue: "3"), title: "Moby-Dick", authors: ["Herman Melville"], files: [file("remove-test-3")]
        ))
        imported = SourcedBook(source: .files, book: LibraryBook(
            id: LibraryBookID(rawValue: "alice"), title: "Alice", authors: ["Lewis Carroll"], files: [file("remove-test-alice")]
        ))
        for book in [downloaded, imported] {
            let file = try #require(book.book.readableFile)
            try Data("epub".utf8).write(to: #require(files.store.url(for: file)))
            try model.library.onIPhone.record(book)
        }
        try model.library.recents.record(downloaded)
        try model.library.finished.set(true, for: downloaded.id)
        try model.servers.save(SavedServer(id: Self.server, kind: .bookOrbit, address: "http://localhost:3300", name: "BookOrbit"))
        await model.library.connect(Self.bookOrbit(id: Self.server, account: "octavo"))
        for book in [downloaded, imported] {
            let key = try #require(book.book.readableFile?.storageKey)
            try model.places.store.save(ReadingPosition(cfi: "epubcfi(/6/4!/4/2)", fraction: 0.3), forBook: key, needsPush: true)
            try model.bookmarks.save([], forBook: key)
        }
    }

    static func bookOrbit(id: LibrarySourceID, account: String) -> LibraryServer {
        LibraryServer(id: id, name: "BookOrbit", address: "localhost:3300", username: account, signsIn: true, source: StubLibrarySource())
    }

    private func key(_ book: SourcedBook) -> String {
        book.book.readableFile!.storageKey
    }

    private func hasPlace(_ book: SourcedBook) -> Bool {
        model.places.store.progress(forBook: key(book)) != nil
    }

    private func hasBookmarks(_ book: SourcedBook) -> Bool {
        FileManager.default.fileExists(atPath: model.bookmarks.fileURL(forBook: key(book)).path)
    }

    @Test func countsTheServersDownloadsNotImportedOnes() {
        #expect(model.serverDownloads().map(\.book.id) == [downloaded.id])
        #expect(model.downloads().count == 2)
    }

    @Test func keepingBooksLeavesThemOnTheIPhone() async {
        await model.removeServer(removingBooks: false)
        #expect(model.library.server == nil)
        #expect(model.needsSetup)
        #expect(model.servers.load() == nil)
        #expect(model.opener.localFile(for: downloaded.book) != nil)
        #expect(model.downloads().map(\.book.id).contains(downloaded.id), "Storage still lists it")
        #expect(model.library.recents.records().isEmpty)
        #expect(!model.library.finished.contains(downloaded.id))
    }

    @Test func removingBooksDeletesTheServersOnly() async {
        await model.removeServer(removingBooks: true)
        #expect(model.opener.localFile(for: downloaded.book) == nil)
        #expect(model.opener.localFile(for: imported.book) != nil)
        #expect(model.library.onIPhone.books().map(\.id) == [imported.id])
    }

    // Kept books known only from Continue reading (opened before the
    // iPhone kept its list) stay listed once those records go.
    @Test func aKeptBookKnownOnlyFromContinueReadingStaysListed() async throws {
        try model.library.onIPhone.remove(downloaded.id)
        #expect(model.serverDownloads().count == 1)
        await model.removeServer(removingBooks: false)
        #expect(model.downloads().map(\.book.id).contains(downloaded.id))
    }

    // BookOrbit numbers files from 1 on every server: another server (or
    // account) must not find the removed one's book 3 as its own.
    @Test func anotherServerFindsNoneOfTheRemovedOnesBooks() async {
        await model.removeServer(removingBooks: false)
        await model.library.connect(Self.bookOrbit(id: SavedServer.newID(), account: "someone-else"))
        #expect(model.opener.localFile(for: downloaded.book) == nil)
        #expect(!hasPlace(downloaded))
        #expect(!hasBookmarks(downloaded))
        #expect(model.downloads().map(\.book.id) == [imported.id])
        #expect(model.opener.localFile(for: imported.book) != nil, "imported books stay")
        #expect(hasPlace(imported))
        #expect(hasBookmarks(imported))
    }

    // Which server a removed one was: its kind, full address (two behind
    // one proxy differ by path) and account, and a catalog's key.
    @Test func identitiesTellServersApart() throws {
        let home = SavedServer(id: SavedServer.newID(), kind: .bookOrbit, address: "https://nas.example.com/bookorbit", name: "BookOrbit", username: "adam")
        var other = home
        other.id = SavedServer.newID()
        #expect(home.libraryServer()?.identity == other.libraryServer()?.identity, "the same server at a new ID")
        other.address = "https://nas.example.com/friends-bookorbit"
        #expect(home.libraryServer()?.identity != other.libraryServer()?.identity)
        other = home
        other.username = "sam"
        #expect(home.libraryServer()?.identity != other.libraryServer()?.identity)
        let key1 = try #require(OPDSURLSecret("0123456789abcdef0123456789abcdef"))
        let key2 = try #require(OPDSURLSecret("fedcba9876543210fedcba9876543210"))
        let catalog = "https://kavita.example.com/api/opds/\(OPDSURLSecret.placeholder)"
        #expect(LibraryServer.origin(kind: .opds, address: catalog, secret: key1) != LibraryServer.origin(kind: .opds, address: catalog, secret: key2))
        #expect(LibraryServer.origin(kind: .opds, address: catalog, secret: key1) != LibraryServer.origin(kind: .opds, address: catalog, secret: key1),
                "a catalog with a key never matches, as nothing derived from its key is kept")
        #expect(!LibraryServer.origin(kind: .opds, address: catalog, secret: key1).contains(key1.value))
    }

    // The same server and account, at a new ID: its books are where they
    // were, as "Keep books on iPhone" promised.
    @Test func theSameServerComingBackFindsItsBooks() async {
        await model.removeServer(removingBooks: false)
        await model.library.connect(Self.bookOrbit(id: SavedServer.newID(), account: "octavo"))
        #expect(model.opener.localFile(for: downloaded.book) != nil)
        #expect(hasPlace(downloaded))
        #expect(hasBookmarks(downloaded))
        #expect(model.removedServers.load() == nil)
    }

    // A download still running when the server goes doesn't land.
    @Test func aRunningDownloadStopsAndLeavesNothing() async throws {
        let slow = LibraryBook(id: LibraryBookID(rawValue: "slow"), title: "Slow")
        await model.library.connect(LibraryServer(
            id: Self.server, name: "BookOrbit", address: "localhost:3300", username: "octavo",
            source: StubLibrarySource(downloadTime: .milliseconds(300))
        ))
        model.downloadBook(SourcedBook(source: Self.server, book: slow))
        await model.removeServer(removingBooks: true)
        try await Task.sleep(for: .milliseconds(600))
        let file = try #require(StubLibrarySource().files.first)
        #expect(files.store.localFile(for: file) == nil)
        #expect(model.opener.status(of: slow) == .notDownloaded)
        #expect(model.reading == nil)
    }

    @Test func theQuestionCountsTheBooks() {
        let one = DownloadedBook(book: downloaded, url: URL(filePath: "/a.epub"), size: 2_000_000, downloadedAt: .now)
        let two = DownloadedBook(book: imported, url: URL(filePath: "/b.epub"), size: 46_000_000, downloadedAt: .now)
        #expect(ServerSettingsPage.removalMessage([]) == "You can add it again any time.")
        #expect(ServerSettingsPage.removalMessage([one]) == "Its downloaded book uses 2 MB. Remove it too, or keep it on this iPhone?")
        #expect(ServerSettingsPage.removalMessage([one, two]) == "Its 2 downloaded books use 48 MB. Remove them too, or keep them on this iPhone?")
    }
}

/// Sign out (decision 24): the server stays, signed out.
@MainActor
@Suite(.temporaryFiles)
struct SignOutTests {
    @Test func signingOutShowsTheBannerAndKeepsTheServer() async {
        let model = makeShell()
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "BookOrbit", signsIn: true, source: StubLibrarySource()))
        model.signOut()
        #expect(model.library.connectionProblem == .signedOut(server: "BookOrbit"))
        #expect(model.library.server != nil)
    }

    @Test func aCatalogWithoutAPasswordHasNothingToSignOutOf() async {
        let model = makeShell()
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "COPS", source: StubLibrarySource()))
        model.signOut()
        #expect(model.library.connectionProblem == nil)
    }
}

/// Books on iPhone's orders (Adam, 2026-11-02).
struct DownloadOrderTests {
    static func book(_ title: String, by author: String, size: Int64, day: Double) -> DownloadedBook {
        DownloadedBook(
            book: SourcedBook(source: .files, book: LibraryBook(id: LibraryBookID(rawValue: title), title: title, authors: [author])),
            url: URL(filePath: "/\(title).epub"), size: size, downloadedAt: Date(timeIntervalSince1970: day * 86_400)
        )
    }

    static let books = [
        book("Moby-Dick", by: "Herman Melville", size: 800, day: 3),
        book("Pride and Prejudice", by: "Jane Austen", size: 25_000, day: 1),
        book("The Time Machine", by: "H. G. Wells", size: 300, day: 2),
    ]

    @Test(arguments: [
        (DownloadOrder.size, ["Pride and Prejudice", "Moby-Dick", "The Time Machine"]),
        (.title, ["Moby-Dick", "Pride and Prejudice", "The Time Machine"]),
        (.author, ["Pride and Prejudice", "Moby-Dick", "The Time Machine"]),
        (.downloaded, ["Moby-Dick", "The Time Machine", "Pride and Prejudice"]),
    ])
    func sorts(_ order: DownloadOrder, _ titles: [String]) {
        #expect(order.sorted(Self.books).map(\.book.book.title) == titles)
    }

    @Test func summarisesCountAndSize() {
        #expect(Self.books.summary() == "3 · 26 KB")
        #expect(Self.books.summary(books: true) == "3 books · 26 KB")
        #expect(Array(Self.books.prefix(1)).summary(books: true) == "1 book · 800 bytes")
        #expect([DownloadedBook]().summary() == "None")
    }
}

/// The Licences page reads the notices the app bundles.
struct ThirdPartyNoticeTests {
    static let notices = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "THIRD-PARTY-NOTICES.md")

    @Test func readsEveryComponentWithItsLicence() throws {
        let parsed = ThirdPartyNotice.parse(try String(contentsOf: Self.notices, encoding: .utf8))
        #expect(parsed.map(\.name) == ["foliate-js", "zip.js (bundled by foliate-js)", "fflate (bundled by foliate-js)", "EB Garamond (logo lettering)"])
        #expect(parsed.map(\.license).prefix(3) == ["MIT", "BSD-3-Clause", "MIT"])
        let foliate = try #require(parsed.first)
        #expect(foliate.paragraphs.first == "MIT License")
        #expect(foliate.paragraphs.contains { $0.hasPrefix("Permission is hereby granted, free of charge, to any person obtaining a copy of this software") })
        #expect(parsed.last?.paragraphs.isEmpty == false, "a credit without a text keeps its notes")
    }

    @Test func theAppBundlesThem() {
        #expect(ThirdPartyNotice.bundled().count == 4)
    }
}
