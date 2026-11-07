import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Settings (step 14): its pages folded and unfolded, Remove server, the
/// books on the iPhone and the licences.
@MainActor
@Suite(.temporaryFiles)
struct SettingsNavigationTests {
    private func shell(_ spread: Spread) -> ShellModel {
        let model = makeShell()
        model.lastSpread = spread
        return model
    }

    // Folded, a row's page slides in over the list, and Back returns to it.
    @Test func foldedAPageGoesOverTheList() {
        let model = shell(.duoFolded)
        model.openSettings()
        model.push(.settingsPage(.storage))
        #expect(model[path: .home].routes == [.settings, .settingsPage(.storage)])
        #expect(model[path: .home].lastMove == .push)
        model.back(.home)
        #expect(model[path: .home].routes == [.settings])
    }

    // Unfolded, the list stays and the right page changes without a slide.
    @Test func unfoldedAPageReplacesTheOneBesideTheList() {
        let model = shell(.duoUnfolded)
        model.openSettings()
        model.push(.settingsPage(.storage))
        #expect(model[path: .home].routes == [.settings, .settingsPage(.storage)])
        #expect(model[path: .home].lastMove == .replace)
        model.push(.settingsPage(.licences))
        #expect(model[path: .home].routes == [.settings, .settingsPage(.licences)])
        #expect(model[path: .home].lastMove == .replace)
    }

    // Unfolded, the list and its page are one screen: Back leaves both.
    @Test func unfoldedBackLeavesSettings() {
        let model = shell(.duoUnfolded)
        model.openSettings()
        model.push(.settingsPage(.server(SampleLibrarySource.id)))
        model.back(.home)
        #expect(model[path: .home].routes.isEmpty)
        #expect(model[path: .home].lastMove == .pop)
    }

    // Folded on a page, then unfolded: Back leaves the list too, as the two
    // are one screen now.
    @Test func backAfterUnfoldingOnAPageLeavesSettings() {
        let model = shell(.duoFolded)
        model.openSettings()
        model.push(.settingsPage(.storage))
        model.lastSpread = .duoUnfolded
        model.back(.home)
        #expect(model[path: .home].routes.isEmpty)
    }

    // A screen opened from a page (Sign in again) goes back to the page.
    @Test func backFromAScreenOverAPageIsOneStep() {
        let model = shell(.duoUnfolded)
        model.openSettings()
        model.push(.settingsPage(.server(SampleLibrarySource.id)))
        model.push(.signInAgain(SampleLibrarySource.id))
        #expect(model[path: .home].lastMove == .push)
        model.back(.home)
        #expect(model[path: .home].routes == [.settings, .settingsPage(.server(SampleLibrarySource.id))])
    }

    // Switching tabs, the tab going out of sight measures one page; the tab
    // on screen still goes by its own two.
    @Test func eachTabGoesByItsOwnSpread() {
        let model = shell(.duoFolded)
        model.spreads[.home] = .duoUnfolded
        model.spreads[.library] = .duoFolded
        model.openSettings()
        model.push(.settingsPage(.storage))
        #expect(model[path: .home].lastMove == .replace)
        model.back(.home)
        #expect(model[path: .home].routes.isEmpty)
    }

    // Without the list beneath, a page opens over what's there like any
    // screen.
    @Test func aPageWithoutItsListIsPushed() {
        let model = shell(.duoUnfolded)
        model.push(.settingsPage(.storage))
        #expect(model[path: .home].routes == [.settingsPage(.storage)])
        #expect(model[path: .home].lastMove == .push)
        model.back(.home)
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
        let downloadedFile = try #require(downloaded.book.readableFile)
        try Data("epub".utf8).write(to: #require(files.store.url(for: downloadedFile, in: downloaded.source)))
        let incoming = URL.testDirectory.appending(path: "\(UUID().uuidString).epub", directoryHint: .notDirectory)
        try Data("epub".utf8).write(to: incoming)
        try files.store.imported.add(LibraryBookDetails(book: imported.book), file: incoming, cover: nil)
        for book in [downloaded, imported] { try model.library.onIPhone.record(book) }
        try model.library.recents.record(downloaded)
        try model.library.finished.set(true, for: downloaded.id)
        try model.servers.save(SavedServer(id: Self.server, kind: .bookOrbit, address: "http://localhost:3300", name: "BookOrbit"))
        await model.library.connect(Self.bookOrbit(id: Self.server, account: "octavo"))
        for book in [downloaded, imported] {
            let key = try #require(book.storageKey)
            try model.places.store.save(ReadingPosition(cfi: "epubcfi(/6/4!/4/2)", fraction: 0.3), forBook: key, needsPush: true)
            try model.bookmarks.save([], forBook: key)
        }
    }

    static func bookOrbit(id: LibrarySourceID, account: String) -> LibraryServer {
        LibraryServer(
            id: id, name: "BookOrbit", address: "localhost:3300", username: account, signsIn: true,
            origin: LibraryServer.origin(kind: .bookOrbit, address: "http://localhost:3300"), source: StubLibrarySource()
        )
    }

    private func key(_ book: SourcedBook) -> String {
        book.storageKey!
    }

    private func hasPlace(_ book: SourcedBook) -> Bool {
        model.places.store.progress(forBook: key(book)) != nil
    }

    private func hasBookmarks(_ book: SourcedBook) -> Bool {
        FileManager.default.fileExists(atPath: model.bookmarks.fileURL(forBook: key(book)).path)
    }

    @Test func countsTheServersDownloadsNotImportedOnes() {
        #expect(model.downloads(on: Self.server).map(\.book.id) == [downloaded.id])
        #expect(model.downloads().count == 2)
    }

    @Test func keepingBooksLeavesThemOnTheIPhone() async {
        await model.serverActions.remove(Self.server, removingBooks: false)
        #expect(model.library.server == nil)
        #expect(model.needsSetup)
        #expect(model.servers.load().servers.isEmpty)
        #expect(model.opener.localFile(for: downloaded) != nil)
        #expect(model.downloads().map(\.book.id).contains(downloaded.id), "Storage still lists it")
        #expect(model.library.recents.records().isEmpty)
        #expect(!model.library.finished.contains(downloaded.id))
    }

    @Test func removingBooksDeletesTheServersOnly() async {
        await model.serverActions.remove(Self.server, removingBooks: true)
        #expect(model.opener.localFile(for: downloaded) == nil)
        #expect(model.opener.localFile(for: imported) != nil)
        #expect(model.library.onIPhone.books().map(\.id) == [imported.id])
    }

    // Nothing of it stays on the iPhone, its address and account included
    // (Adam, 2026-11-05).
    @Test func removingBooksLeavesNothingOfTheServer() async {
        await model.serverActions.remove(Self.server, removingBooks: true)
        #expect(!hasPlace(downloaded))
        #expect(!hasBookmarks(downloaded))
        #expect(model.removedServers.load().isEmpty)
        #expect(hasPlace(imported), "imported books stay")
        #expect(hasBookmarks(imported))
    }

    @Test func keepingBooksKeepsItsPlacesToo() async {
        await model.serverActions.remove(Self.server, removingBooks: false)
        #expect(hasPlace(downloaded))
        #expect(hasBookmarks(downloaded))
        #expect(model.removedServers.load().map(\.id) == [Self.server])
    }

    // Kept books known only from Continue reading (opened before the
    // iPhone kept its list) stay listed once those records go.
    @Test func aKeptBookKnownOnlyFromContinueReadingStaysListed() async throws {
        try model.library.onIPhone.remove(downloaded.id)
        #expect(model.downloads(on: Self.server).count == 1)
        await model.serverActions.remove(Self.server, removingBooks: false)
        #expect(model.downloads().map(\.book.id).contains(downloaded.id))
    }

    // BookOrbit numbers files from 1 on every server: another server (or
    // account) must not find the removed one's book 3 as its own.
    @Test func anotherServerFindsNoneOfTheRemovedOnesBooks() async {
        await model.serverActions.remove(Self.server, removingBooks: false)
        let other = SavedServer.newID()
        await model.library.connect(Self.bookOrbit(id: other, account: "someone-else"))
        let sameNumber = SourcedBook(source: other, book: downloaded.book)
        #expect(model.opener.localFile(for: sameNumber) == nil)
        #expect(!hasPlace(sameNumber))
        #expect(!hasBookmarks(sameNumber))
        #expect(model.opener.localFile(for: downloaded) != nil, "the kept book is still its own")
        #expect(model.opener.localFile(for: imported) != nil, "imported books stay")
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
        await model.serverActions.remove(Self.server, removingBooks: false)
        let back = SavedServer(id: SavedServer.newID(), kind: .bookOrbit, address: "http://localhost:3300", name: "BookOrbit", username: "octavo")
        model.setup.finished(back)
        let same = SourcedBook(source: back.id, book: downloaded.book)
        #expect(model.opener.localFile(for: same) != nil)
        #expect(hasPlace(same))
        #expect(hasBookmarks(same))
        #expect(model.library.onIPhone.books().contains(same))
        #expect(model.removedServers.load().isEmpty)
    }

    // A download still running when the server goes doesn't land.
    @Test func aRunningDownloadStopsAndLeavesNothing() async throws {
        let slow = LibraryBook(id: LibraryBookID(rawValue: "slow"), title: "Slow")
        await model.library.connect(LibraryServer(
            id: Self.server, name: "BookOrbit", address: "localhost:3300", username: "octavo",
            source: StubLibrarySource(downloadTime: .milliseconds(300))
        ))
        model.downloadBook(SourcedBook(source: Self.server, book: slow))
        await model.serverActions.remove(Self.server, removingBooks: true)
        try await Task.sleep(for: .milliseconds(600))
        let file = try #require(StubLibrarySource().files.first)
        #expect(files.store.localFile(for: file, in: Self.server) == nil)
        #expect(model.opener.status(of: SourcedBook(source: Self.server, book: slow)) == .notDownloaded)
        #expect(model.reader.reading == nil)
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
        model.serverActions.signOut(SampleLibrarySource.id)
        #expect(model.library.connectionProblem == .signedOut(server: "BookOrbit"))
        #expect(model.library.server != nil)
    }

    /// Step 16: Sign out is noted with the saved server before the
    /// sign-in is deleted, so a Keychain that can't delete it now is
    /// cleared at the next launch (`KeychainSweep`); signing in again
    /// clears the note.
    @Test func signingOutIsNotedUntilSignedInAgain() async throws {
        let model = makeShell()
        let id = SavedServer.newID()
        defer { try? ServerCredentials.removeAll(serverID: id.rawValue) }
        let catalog = try #require(URL(string: "http://nas.lan/opds"))
        let passwords = KeychainPasswordStore(serverID: id.rawValue)
        try await passwords.save(PasswordCredentials(username: "adam", password: "old"))
        try model.servers.save(SavedServer(id: id, kind: .opds, address: catalog.absoluteString, name: "COPS", username: "adam", authScheme: .basic))
        let source = OPDSSource(catalogURL: catalog, transport: OpenCatalog(), credentials: passwords, authScheme: .basic)
        await model.library.connect(LibraryServer(id: id, name: "COPS", username: "adam", signsIn: true, source: source))

        model.serverActions.signOut(id)
        #expect(model.servers.load()[id]?.signedOut == true)
        var waited = 0
        while try await passwords.load() != nil, waited < 200 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        #expect(try await passwords.load() == nil)

        try await model.serverActions.signInAgain(id, username: "adam", password: "new")
        #expect(model.servers.load()[id]?.signedOut == nil)
        #expect(try await passwords.load()?.password == "new")
    }

    @Test func aCatalogWithoutAPasswordHasNothingToSignOutOf() async {
        let model = makeShell()
        await model.library.connect(LibraryServer(id: SampleLibrarySource.id, name: "COPS", source: StubLibrarySource()))
        model.serverActions.signOut(SampleLibrarySource.id)
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
        #expect(parsed.map(\.name) == ["foliate-js", "zip.js (bundled by foliate-js)", "fflate (bundled by foliate-js)",
            "Atkinson Hyperlegible Next (reader font)", "OpenDyslexic (reader font)", "EB Garamond (logo lettering)",
            "Pride and Prejudice (the sample book), Standard Ebooks",
        ])
        #expect(parsed.map(\.license).prefix(5) == ["MIT", "BSD-3-Clause", "MIT", "SIL Open Font License 1.1", "SIL Open Font License 1.1"])
        let foliate = try #require(parsed.first)
        #expect(foliate.paragraphs.first == "MIT License")
        #expect(foliate.paragraphs.contains { $0.hasPrefix("Permission is hereby granted, free of charge, to any person obtaining a copy of this software") })
        #expect(parsed.last?.paragraphs.isEmpty == false, "a credit without a text keeps its notes")
    }

    // The OFL travels with the fonts where people can read it: their
    // copyright and the licence's own text.
    @Test func theBundledFontsShowTheirLicence() throws {
        let parsed = ThirdPartyNotice.parse(try String(contentsOf: Self.notices, encoding: .utf8))
        for (name, copyright) in [("Atkinson Hyperlegible Next (reader font)", "Copyright 2020-2024 The Atkinson Hyperlegible Next Project Authors"),
                                  ("OpenDyslexic (reader font)", "with Reserved Font Name OpenDyslexic")] {
            let font = try #require(parsed.first { $0.name == name })
            #expect(font.paragraphs.first?.contains(copyright) == true)
            #expect(font.paragraphs.contains { $0.hasPrefix("PERMISSION & CONDITIONS") })
        }
    }

    @Test func theAppBundlesThem() {
        #expect(ThirdPartyNotice.bundled().count == 7)
    }
}

/// A catalog that answers every request with an empty feed.
private struct OpenCatalog: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let feed = #"<feed xmlns="http://www.w3.org/2005/Atom"><title>COPS</title></feed>"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/atom+xml;profile=opds-catalog"])!
        return (Data(feed.utf8), response)
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        throw URLError(.unsupportedURL)
    }
}
