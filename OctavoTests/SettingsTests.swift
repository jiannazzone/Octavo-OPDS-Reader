import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Settings (step 14): its pages folded and unfolded, Remove server, the
/// books on the iPhone and the licences.
@MainActor
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
        await model.library.connect(LibraryServer(id: Self.server, name: "BookOrbit", source: StubLibrarySource()))
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
