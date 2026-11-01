import Foundation
import OctavoKit
import Synchronization
import Testing
@testable import Octavo

/// Which pages fail, switchable while a test runs.
private nonisolated final class Faults: Sendable {
    private let errors: Mutex<[String: any Error & Sendable]>

    init(_ errors: [String: any Error & Sendable] = [:]) {
        self.errors = Mutex(errors)
    }

    func error(for link: String) -> (any Error)? { errors.withLock { $0[link] } }
    func set(_ link: String, _ error: (any Error & Sendable)?) { errors.withLock { $0[link] = error } }
}

/// A library made of fixed pages, some of which fail.
private nonisolated struct PagedSource: LibrarySource {
    var pages: [String: LibraryFeed] = [:]
    var faults = Faults()
    var rootChips = [LibraryEntry(kind: .feed, title: "All", link: LibraryLink(rawValue: "all"))]

    func root() async throws -> LibraryRoot {
        LibraryRoot(chips: rootChips, search: .unavailable, recentlyAdded: LibraryLink(rawValue: "recent"),
                    continueReading: LibraryLink(rawValue: "reading"))
    }

    func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        if let error = faults.error(for: link.rawValue) { throw error }
        return pages[link.rawValue] ?? LibraryFeed()
    }

    func search(_ query: String) async throws -> LibrarySearchResults { LibrarySearchResults(query: query) }
    func details(for book: LibraryBook) async throws -> LibraryBookDetails { LibraryBookDetails(book: book) }
    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data { throw LibraryError.notFound }
    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw LibraryError.notFound
    }
}

/// A server whose chips fail with something other than a connection
/// problem.
private nonisolated struct FailingRootSource: LibrarySource {
    func root() async throws -> LibraryRoot { throw LibraryError.server(status: 500, message: nil) }
    func feed(_ link: LibraryLink) async throws -> LibraryFeed { LibraryFeed() }
    func search(_ query: String) async throws -> LibrarySearchResults { LibrarySearchResults(query: query) }
    func details(for book: LibraryBook) async throws -> LibraryBookDetails { LibraryBookDetails(book: book) }
    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data { throw LibraryError.notFound }
    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw LibraryError.notFound
    }
}

private func book(_ id: String, hoursAgo: Double? = nil, progress: Double? = nil) -> LibraryBook {
    LibraryBook(id: LibraryBookID(rawValue: id), title: id, progress: progress,
                lastReadAt: hoursAgo.map { Date(timeIntervalSinceReferenceDate: 1_000_000 - $0 * 3600) })
}

private func link(_ rawValue: String) -> LibraryLink { LibraryLink(rawValue: rawValue) }

private let server = LibrarySourceID(rawValue: "server")

private func sourced(_ book: LibraryBook, from source: LibrarySourceID = server) -> SourcedBook {
    SourcedBook(source: source, book: book)
}

private func temporaryRecents() -> RecentBooks {
    RecentBooks(fileURL: URL.temporaryDirectory.appending(path: "RecentBooks-\(UUID().uuidString).json"))
}

@MainActor
private func connected(_ source: some LibrarySource, recents: RecentBooks = temporaryRecents()) async -> LibraryModel {
    let library = LibraryModel(recents: recents)
    await library.connect(LibraryServer(id: server, name: "Shelf", detail: "", source: source))
    return library
}

@MainActor
struct FeedModelTests {
    static let pages = [
        "a": LibraryFeed(books: [book("1"), book("2")], total: 3, next: link("a?page=1")),
        "a?page=1": LibraryFeed(books: [book("3")], total: 3),
    ]

    @Test func loadsAPageAtATime() async throws {
        let library = await connected(PagedSource(pages: Self.pages))
        let feed = try #require(library.feed(link("a"), from: server))

        await feed.load()
        #expect(feed.books.map(\.title) == ["1", "2"])
        #expect(feed.hasMore)
        await feed.loadMore()
        #expect(feed.books.map(\.title) == ["1", "2", "3"])
        #expect(!feed.hasMore)
        #expect(feed.total == 3)
    }

    @Test func loadAllFollowsEveryPage() async throws {
        let library = await connected(PagedSource(pages: Self.pages))
        let feed = try #require(library.feed(link("a"), from: server))
        await feed.loadAll()
        #expect(feed.books.count == 3)
    }

    // Folding rebuilds the views; the list they find is the same one.
    @Test func keepsOneModelPerList() async throws {
        let library = await connected(PagedSource(pages: Self.pages))
        let feed = try #require(library.feed(link("a"), from: server))
        #expect(library.feed(link("a"), from: server) === feed)
        #expect(library.feed(link("a"), from: LibrarySourceID(rawValue: "elsewhere")) == nil)
    }

    @Test func aConnectionFailureBecomesTheBanner() async throws {
        let library = await connected(PagedSource(faults: Faults(["a": URLError(.cannotConnectToHost)])))
        let feed = try #require(library.feed(link("a"), from: server))
        await feed.load()
        #expect(feed.state == .failed)
        #expect(library.connectionProblem == .unreachable(server: "Shelf"))
    }

    @Test func signingOutBecomesTheBanner() async throws {
        let library = await connected(PagedSource(faults: Faults(["a": LibraryError.signedOut])))
        await library.feed(link("a"), from: server)?.load()
        #expect(library.connectionProblem == .signedOut(server: "Shelf"))
    }

    @Test func otherFailuresStayWithTheList() async throws {
        let library = await connected(PagedSource(faults: Faults(["a": LibraryError.server(status: 500, message: nil)])))
        let feed = try #require(library.feed(link("a"), from: server))
        await feed.load()
        #expect(feed.state == .failed)
        #expect(library.connectionProblem == nil)
    }

    @Test func aFailedPageRetriesThatPage() async throws {
        let faults = Faults(["a?page=1": URLError(.timedOut)])
        let library = await connected(PagedSource(pages: Self.pages, faults: faults))
        let feed = try #require(library.feed(link("a"), from: server))
        await feed.load()
        await feed.loadMore()
        #expect(feed.state == .failed)
        #expect(feed.books.count == 2)

        faults.set("a?page=1", nil)
        await feed.retry()
        #expect(feed.books.map(\.title) == ["1", "2", "3"])
    }

    @Test func firstRouteFollowsWhatShowsFirst() async throws {
        let authors = [
            LibraryEntry(kind: .author, title: "Mary Shelley", sortName: "Shelley, Mary", link: link("authors/2")),
            LibraryEntry(kind: .author, title: "Jane Austen", sortName: "Austen, Jane", link: link("authors/1")),
        ]
        let library = await connected(PagedSource(pages: ["authors": LibraryFeed(entries: authors), "a": Self.pages["a"]!]))

        let authorList = try #require(library.feed(link("authors"), from: server))
        await authorList.load()
        #expect(authorList.isAuthorList)
        #expect(authorList.firstRoute == .feed(authors[1], from: server))

        let books = try #require(library.feed(link("a"), from: server))
        await books.load()
        #expect(books.firstRoute == .cover(sourced(book("1"))))
    }
}

@MainActor
struct LibraryModelTests {
    @Test func aFailedContinueReadingIsntAnEmptyOne() async {
        let library = await connected(PagedSource(faults: Faults(["reading": LibraryError.server(status: 500, message: nil)])))
        #expect(library.homeLoaded)
        #expect(library.continueReading.isEmpty)
        #expect(library.continueReadingFailed)
        #expect(library.connectionProblem == nil)
    }

    @Test func aFailedRootSaysSo() async {
        let library = await connected(FailingRootSource())
        #expect(library.root == nil)
        #expect(library.rootFailed)
        #expect(library.connectionProblem == nil)
    }

    // A collection row asks the preview source for its few covers, and
    // keeps the full list apart.
    @Test func rowsPreviewFromTheSmallPageSource() async throws {
        let full = PagedSource(pages: ["c": LibraryFeed(books: (0..<50).map { book("\($0)") })])
        let small = PagedSource(pages: ["c": LibraryFeed(books: (0..<3).map { book("\($0)") })])
        let library = LibraryModel(recents: temporaryRecents())
        await library.connect(LibraryServer(id: server, name: "Shelf", detail: "", source: full, previewSource: small))

        let preview = try #require(library.preview(link("c"), from: server))
        await preview.load()
        #expect(preview.books.count == 3)
        let list = try #require(library.feed(link("c"), from: server))
        #expect(list !== preview)
        await list.load()
        #expect(list.books.count == 50)
    }

    @Test func withoutAPreviewSourceRowsShareTheList() async {
        let library = await connected(PagedSource())
        #expect(library.preview(link("c"), from: server) === library.feed(link("c"), from: server))
    }

    @Test func startsOnTheFirstChip() async {
        let library = await connected(PagedSource())
        #expect(library.chip == link("all"))
    }

    @Test func homeMergesTheServersListWithTheIPhones() async throws {
        let recents = temporaryRecents()
        try recents.record(sourced(book("opened-here")), at: Date(timeIntervalSinceReferenceDate: 1_000_000 - 1.5 * 3600))
        // From a server that's no longer connected: can't be opened.
        try recents.record(sourced(book("gone"), from: LibrarySourceID(rawValue: "old")), at: .distantFuture)
        let source = PagedSource(pages: [
            "reading": LibraryFeed(books: [book("read-1h-ago", hoursAgo: 1), book("read-2h-ago", hoursAgo: 2)]),
            "recent": LibraryFeed(books: (0..<30).map { book("new-\($0)") }),
        ])

        let library = await connected(source, recents: recents)

        #expect(library.homeLoaded)
        #expect(library.continueReading.map(\.book.title) == ["read-1h-ago", "opened-here", "read-2h-ago"])
        #expect(library.newBooks.count == LibraryModel.newBooksLimit)
        #expect(library.newBooks.first?.source == server)
    }

    @Test func aFailedHomeKeepsWhatItShowed() async {
        let faults = Faults()
        let library = await connected(PagedSource(pages: ["reading": LibraryFeed(books: [book("1")])], faults: faults))
        #expect(library.continueReading.map(\.book.title) == ["1"])

        faults.set("reading", URLError(.notConnectedToInternet))
        await library.loadHome()
        #expect(library.continueReading.map(\.book.title) == ["1"])
        #expect(library.connectionProblem == .unreachable(server: "Shelf"))
    }

    @Test func disconnectingForgetsTheServer() async {
        let library = await connected(PagedSource())
        library.disconnect()
        #expect(library.server == nil)
        #expect(library.source(for: server) == nil)
        #expect(library.feed(link("a"), from: server) == nil)
    }
}

struct ContinueReadingTests {
    static let iPhoneDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func newestFirstAcrossBothLists() {
        let merged = ContinueReading.merge(
            server: [sourced(book("a", hoursAgo: 1)), sourced(book("b", hoursAgo: 3))],
            iPhone: [RecentBooks.Record(book: sourced(book("c")), openedAt: Self.iPhoneDate.addingTimeInterval(-2 * 3600))]
        )
        #expect(merged.map(\.book.title) == ["a", "c", "b"])
    }

    @Test func aBookInBothShowsOnceWithTheServersProgress() {
        let merged = ContinueReading.merge(
            server: [sourced(book("a", hoursAgo: 5, progress: 0.5)), sourced(book("b", hoursAgo: 1))],
            iPhone: [RecentBooks.Record(book: sourced(book("a", progress: 0.2)), openedAt: Self.iPhoneDate)]
        )
        #expect(merged.map(\.book.title) == ["a", "b"])
        #expect(merged[0].book.progress == 0.5)
    }

    @Test func undatedBooksKeepTheirOrderAfterDatedOnes() {
        let merged = ContinueReading.merge(
            server: [sourced(book("x")), sourced(book("y")), sourced(book("z", hoursAgo: 9))],
            iPhone: []
        )
        #expect(merged.map(\.book.title) == ["z", "x", "y"])
    }

    @Test func showsFiveAtMost() {
        let merged = ContinueReading.merge(server: (0..<8).map { sourced(book("\($0)", hoursAgo: Double($0))) }, iPhone: [])
        #expect(merged.map(\.book.title) == ["0", "1", "2", "3", "4"])
    }

    @Test func theSameIDFromAnotherLibraryIsAnotherBook() {
        let merged = ContinueReading.merge(
            server: [sourced(book("1", hoursAgo: 1))],
            iPhone: [RecentBooks.Record(book: sourced(book("1"), from: .files), openedAt: Self.iPhoneDate)]
        )
        #expect(merged.count == 2)
    }
}

struct RecentBooksTests {
    @Test func newestFirstWithoutRepeats() throws {
        let recents = temporaryRecents()
        #expect(recents.records().isEmpty)
        try recents.record(sourced(book("a")), at: Date(timeIntervalSinceReferenceDate: 1))
        try recents.record(sourced(book("b")), at: Date(timeIntervalSinceReferenceDate: 2))
        try recents.record(sourced(book("a")), at: Date(timeIntervalSinceReferenceDate: 3))
        #expect(recents.records().map(\.book.book.title) == ["a", "b"])
        #expect(recents.records().first?.openedAt == Date(timeIntervalSinceReferenceDate: 3))
    }

    @Test func keepsTheLatestTwenty() throws {
        let recents = temporaryRecents()
        for index in 0..<25 { try recents.record(sourced(book("\(index)"))) }
        #expect(recents.records().count == RecentBooks.limit)
        #expect(recents.records().first?.book.book.title == "24")
    }
}

struct AuthorIndexTests {
    static func author(_ sortName: String?, _ title: String = "") -> LibraryEntry {
        LibraryEntry(kind: .author, title: title.isEmpty ? sortName ?? "" : title, sortName: sortName,
                     link: LibraryLink(rawValue: "authors/\(sortName ?? title)"))
    }

    @Test func groupsByTheSortNamesFirstLetter() {
        let sections = AuthorIndex.sections([
            Self.author("Shelley, Mary"), Self.author("Austen, Jane"), Self.author("Carroll, Lewis"), Self.author("Asimov, Isaac"),
        ])
        #expect(sections.map(\.letter) == ["A", "C", "S"])
        #expect(sections[0].entries.map(\.sortName) == ["Asimov, Isaac", "Austen, Jane"])
    }

    @Test func foldsAccentsAndFilesTheRestUnderHash() {
        let sections = AuthorIndex.sections([Self.author("Émile Zola"), Self.author("50 Cent"), Self.author(nil, "zed")])
        #expect(sections.map(\.letter) == ["E", "Z", "#"])
        #expect(sections.last?.entries.map(\.title) == ["50 Cent"])
    }
}
