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
    var tracksFinished = false

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
    RecentBooks(fileURL: URL.testDirectory.appending(path: "RecentBooks-\(UUID().uuidString).json"))
}

/// A library whose lists keep their files in the test's folder, not the app's.
@MainActor
private func temporaryLibrary(recents: RecentBooks = temporaryRecents()) -> LibraryModel {
    LibraryModel(
        recents: recents,
        finished: FinishedBooks(fileURL: URL.testDirectory.appending(path: "FinishedBooks-\(UUID().uuidString).json")),
        onIPhone: BooksOnIPhone(fileURL: URL.testDirectory.appending(path: "BooksOnIPhone-\(UUID().uuidString).json")),
        imported: .temporary()
    )
}

@MainActor
private func connected(_ source: some LibrarySource, recents: RecentBooks = temporaryRecents()) async -> LibraryModel {
    let library = temporaryLibrary(recents: recents)
    await library.connect(LibraryServer(id: server, name: "Shelf", source: source))
    return library
}

@MainActor
@Suite(.temporaryFiles)
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

    @Test func nothingOnTheFirstPageIsAnEmptyList() async throws {
        let library = await connected(PagedSource(pages: Self.pages))
        let empty = try #require(library.feed(link("empty"), from: server))
        #expect(!empty.cameBackEmpty)
        await empty.load()
        #expect(empty.cameBackEmpty)

        let full = try #require(library.feed(link("a"), from: server))
        await full.load()
        #expect(!full.cameBackEmpty)
    }

    // A first load that fails says nothing about the list. A reload that
    // fails leaves it as it was, and `EmptyFeed` says it failed: going to
    // `FeedContent` would load the list a second time.
    @Test func onlyAnAnswerChangesWhetherAListIsEmpty() async throws {
        let faults = Faults()
        faults.set("empty", LibraryError.server(status: 500, message: nil))
        let library = await connected(PagedSource(faults: faults))
        let feed = try #require(library.feed(link("empty"), from: server))
        await feed.load()
        #expect(feed.state == .failed)
        #expect(!feed.cameBackEmpty)

        faults.set("empty", nil)
        await feed.retry()
        #expect(feed.cameBackEmpty)

        faults.set("empty", LibraryError.server(status: 500, message: nil))
        await feed.reload()
        #expect(feed.state == .failed)
        #expect(feed.cameBackEmpty)
    }

    // Folding rebuilds the views; the list they find is the same one.
    // A server whose next page is one already loaded is looping.
    @Test func aListThatLoopsEnds() async throws {
        let authors = [LibraryEntry(kind: .author, title: "Mary Shelley", link: link("authors/2"))]
        let library = await connected(PagedSource(pages: [
            "loop": LibraryFeed(entries: authors, next: link("loop?page=1")),
            "loop?page=1": LibraryFeed(entries: authors, next: link("loop")),
        ]))
        let feed = try #require(library.feed(link("loop"), from: server))
        await feed.loadAll()
        #expect(feed.entries.count == 2)
        #expect(!feed.hasMore)
    }

    // The server decides how many pages there are.
    @Test func loadAllStopsAtItsLimit() async throws {
        var pages: [String: LibraryFeed] = [:]
        for page in 0..<10 {
            pages["p\(page)"] = LibraryFeed(books: [book("\(page)")], next: link("p\(page + 1)"))
        }
        let library = await connected(PagedSource(pages: pages))
        let feed = try #require(library.feed(link("p0"), from: server))
        await feed.loadAll(maxPages: 4)
        #expect(feed.books.count == 4)
        #expect(feed.hasMore)
    }

    // A list sorted or filtered on the iPhone (#131): every page up to the
    // cap, and `hasMore` says it stopped there.
    @Test func loadingAWholeListStopsAtItsCap() async throws {
        var pages: [String: LibraryFeed] = [:]
        for page in 0..<10 {
            pages["p\(page)"] = LibraryFeed(books: [book("\(page)a"), book("\(page)b")], next: page < 9 ? link("p\(page + 1)") : nil)
        }
        let library = await connected(PagedSource(pages: pages))
        let capped = try #require(library.feed(link("p0"), from: server))
        await capped.loadAll(maxBooks: 7)
        #expect(capped.books.count == 8)
        #expect(capped.hasMore)

        let whole = try #require(library.feed(link("p5"), from: server))
        await whole.loadAll(maxBooks: 100)
        #expect(whole.books.count == 10)
        #expect(!whole.hasMore)
    }

    // A page with no books on it ends the load rather than looping on.
    @Test func aWholeListStopsAtAnEmptyPage() async throws {
        let library = await connected(PagedSource(pages: [
            "q0": LibraryFeed(books: [book("1")], next: link("q1")),
            "q1": LibraryFeed(next: link("q2")),
            "q2": LibraryFeed(books: [book("2")]),
        ]))
        let feed = try #require(library.feed(link("q0"), from: server))
        await feed.loadAll(maxBooks: 100)
        #expect(feed.books.map(\.title) == ["1"])
    }

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
}

@MainActor
@Suite(.temporaryFiles)
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
        let library = temporaryLibrary()
        await library.connect(LibraryServer(id: server, name: "Shelf", source: full, previewSource: small))

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
    }

    // Home lists only books in progress: one marked finished leaves, whether
    // the server listed it or it was opened on this iPhone.
    @Test func aBookMarkedFinishedLeavesHome() async throws {
        let recents = temporaryRecents()
        try recents.record(sourced(book("opened-here")), at: Date(timeIntervalSinceReferenceDate: 1_000_000))
        try recents.record(sourced(book("read-1h-ago")), at: Date(timeIntervalSinceReferenceDate: 1_000_000))
        let source = PagedSource(pages: ["reading": LibraryFeed(books: [book("read-1h-ago", hoursAgo: 1)])])
        let library = await connected(source, recents: recents)
        #expect(Set(library.continueReading.map(\.book.title)) == ["opened-here", "read-1h-ago"])

        library.markedFinished(sourced(book("read-1h-ago")).id, true)
        library.markedFinished(sourced(book("opened-here")).id, true)

        #expect(library.continueReading.isEmpty)
        #expect(recents.records().isEmpty)
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

/// What a cover shows, and where it comes from: lists and the iPhone's records
/// each hold their own copy of a book.
@MainActor
@Suite(.temporaryFiles)
struct FinishedCoverTests {
    private static func finished(_ id: String, _ value: Bool?) -> LibraryBook {
        var marked = book(id)
        marked.isFinished = value
        return marked
    }

    /// The same files, as the next launch reads them.
    private func relaunched(_ library: LibraryModel) -> LibraryModel {
        LibraryModel(recents: library.recents, finished: library.finished, onIPhone: library.onIPhone, imported: .temporary())
    }

    @Test func showsTheServersMark() {
        let library = temporaryLibrary()
        #expect(library.isFinished(sourced(Self.finished("1", true))))
        #expect(!library.isFinished(sourced(Self.finished("1", false))))
        #expect(!library.isFinished(sourced(Self.finished("1", nil))))
    }

    @Test func aServerThatKeepsNoMarkUsesTheIPhones() async throws {
        let library = await connected(PagedSource())
        let book = sourced(book("1"))
        try library.finished.set(true, for: book.id)
        library.markedFinished(book.id, true)
        #expect(library.isFinished(book))
        #expect(relaunched(library).isFinished(book))

        try library.finished.set(false, for: book.id)
        library.markedFinished(book.id, false)
        #expect(!library.isFinished(book))
    }

    @Test func aMarkOverridesTheCopyInAList() async throws {
        let source = PagedSource(pages: ["a": LibraryFeed(books: [Self.finished("1", false)])], tracksFinished: true)
        let library = await connected(source)
        let feed = try #require(library.feed(link("a"), from: server))
        await feed.load()
        let copy = sourced(feed.books[0])
        #expect(!library.isFinished(copy))

        library.markedFinished(copy.id, true)
        #expect(library.isFinished(copy))
        library.markedFinished(copy.id, false)
        #expect(!library.isFinished(copy))
        #expect(!library.isFinished(sourced(Self.finished("1", true))))
    }

    // One list loading mustn't undo a mark that another list's older copy
    // only knows through `finishedMarks`.
    @Test func aListAfterTheMarkKeepsItForOlderLists() async throws {
        let source = PagedSource(
            pages: ["old": LibraryFeed(books: [Self.finished("1", false)]), "new": LibraryFeed(books: [Self.finished("1", true)])],
            tracksFinished: true
        )
        let library = await connected(source)
        let old = try #require(library.feed(link("old"), from: server))
        await old.load()
        let copy = sourced(old.books[0])

        library.markedFinished(copy.id, true)
        await library.feed(link("new"), from: server)?.load()
        #expect(library.isFinished(copy))
    }

    @Test func aNewerListChangesAMark() async throws {
        let source = PagedSource(pages: ["new": LibraryFeed(books: [Self.finished("1", false)])], tracksFinished: true)
        let library = await connected(source)
        let copy = sourced(Self.finished("1", false))
        library.markedFinished(copy.id, true)

        await library.feed(link("new"), from: server)?.load()
        #expect(!library.isFinished(copy))
    }

    @Test func aMarkReachesTheIPhonesRecords() async throws {
        let library = await connected(PagedSource(tracksFinished: true))
        let book = sourced(Self.finished("1", false))
        try library.onIPhone.record(book)

        library.markedFinished(book.id, true)
        #expect(library.onIPhone.books().map(\.book.isFinished) == [true])
        #expect(relaunched(library).isFinished(library.onIPhone.books()[0]))
    }

    @Test func takingAMarkOffReachesTheIPhonesRecords() async throws {
        let library = await connected(PagedSource(tracksFinished: true))
        let book = sourced(Self.finished("1", true))
        try library.onIPhone.record(book)
        try library.recents.record(book)

        library.markedFinished(book.id, false)
        #expect(library.onIPhone.books().map(\.book.isFinished) == [false])
        #expect(library.recents.records().map(\.book.book.isFinished) == [false])
    }

    @Test func aListUpdatesTheIPhonesRecords() async throws {
        let source = PagedSource(pages: ["a": LibraryFeed(books: [Self.finished("1", true), Self.finished("2", nil)])], tracksFinished: true)
        let library = await connected(source)
        try library.onIPhone.record(sourced(Self.finished("1", false)))
        try library.onIPhone.record(sourced(Self.finished("2", true)))

        await library.feed(link("a"), from: server)?.load()
        let records = library.onIPhone.books()
        // A list that says nothing about a book changes nothing.
        #expect(records.first { $0.book.id.rawValue == "1" }?.book.isFinished == true)
        #expect(records.first { $0.book.id.rawValue == "2" }?.book.isFinished == true)
    }

    @Test func aBooksDetailsCorrectAnOlderCopy() async throws {
        let library = await connected(PagedSource(tracksFinished: true))
        let copy = sourced(Self.finished("1", false))
        try library.onIPhone.record(copy)

        library.detailsLoaded(sourced(Self.finished("1", true)))
        #expect(library.isFinished(copy))
        #expect(library.onIPhone.books().map(\.book.isFinished) == [true])

        // A server that keeps no mark has nothing to say.
        library.detailsLoaded(sourced(Self.finished("1", nil)))
        #expect(library.isFinished(copy))
    }

    @Test func aRecordMadeLaterKeepsTheLatestMark() async throws {
        let library = await connected(PagedSource(tracksFinished: true))
        let stale = sourced(Self.finished("1", true))
        library.markedFinished(stale.id, false)

        library.bookOpened(stale)
        library.bookDownloading(stale)
        #expect(library.recents.records().map(\.book.book.isFinished) == [false])
        #expect(library.onIPhone.books().map(\.book.isFinished) == [false])
    }

    @Test func removingAServerForgetsItsMarks() async throws {
        let library = await connected(PagedSource())
        let kept = sourced(book("1"))
        try library.finished.set(true, for: kept.id)
        library.markedFinished(kept.id, true)
        let tracked = sourced(Self.finished("2", false))
        library.detailsLoaded(sourced(Self.finished("2", true)))

        library.forgetBooks(of: server)
        #expect(!library.isFinished(kept))
        #expect(!library.isFinished(tracked))
    }
}

@MainActor
struct CoverMarksTests {
    private static let downloading = BookOpener.Status.downloading(fraction: 0.4, opensWhenDone: false)

    @Test func aBookNeitherFinishedNorDownloadedHasNoMark() {
        let statuses: [BookOpener.Status] = [.notDownloaded, .failed(offline: true, opensWhenDone: false), .protected]
        for status in statuses {
            let marks = CoverMarks(finished: false, status: status)
            #expect(marks.isEmpty)
            #expect(marks.download == nil)
            #expect(marks.accessibilityValue == "")
        }
    }

    @Test func aDownloadThatFailedLeavesTheCheck() {
        let marks = CoverMarks(finished: true, status: .failed(offline: false, opensWhenDone: false))
        #expect(!marks.isEmpty)
        #expect(marks.finished)
        #expect(marks.download == nil)
        #expect(marks.accessibilityValue == "Finished")
    }

    @Test func downloadedAlone() {
        let marks = CoverMarks(finished: false, status: .downloaded)
        #expect(!marks.finished)
        #expect(marks.download == .downloaded)
        #expect(marks.accessibilityValue == "Downloaded")
    }

    @Test func finishedAndDownloaded() {
        let marks = CoverMarks(finished: true, status: .downloaded)
        #expect(marks.finished)
        #expect(marks.download == .downloaded)
        #expect(marks.accessibilityValue == "Finished, downloaded")
    }

    @Test func theRingTakesTheArrowsPlace() {
        let marks = CoverMarks(finished: false, status: Self.downloading)
        #expect(marks.download == .downloading(0.4))
        #expect(marks.accessibilityValue == "Downloading, 40%")

        let finished = CoverMarks(finished: true, status: Self.downloading)
        #expect(finished.finished)
        #expect(finished.download == .downloading(0.4))
        #expect(finished.accessibilityValue == "Finished, downloading, 40%")
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

@Suite(.temporaryFiles)
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
        let sections = AuthorIndex.sections([Self.author("Éluard, Paul"), Self.author(nil, "1984"), Self.author(nil, "zed")])
        #expect(sections.map(\.letter) == ["E", "Z", "#"])
        #expect(sections.last?.entries.map(\.title) == ["1984"])
    }

    // BookOrbit sends some sort names first name first.
    @Test func filesByLastNameWhenTheServerDoesnt() {
        let wells = Self.author("H. G. Wells")
        #expect(AuthorIndex.sortKey(wells) == "Wells, H. G.")
        #expect(AuthorIndex.sections([wells, Self.author("Austen, Jane", "Jane Austen")]).map(\.letter) == ["A", "W"])
    }

    @Test func namesReadFirstNameFirst() {
        #expect(AuthorIndex.displayName(Self.author(nil, "Austen, Jane")) == "Jane Austen")
        #expect(AuthorIndex.displayName(Self.author("Austen, Jane", "Jane Austen")) == "Jane Austen")
        #expect(AuthorIndex.displayName(Self.author(nil, "Plato")) == "Plato")
    }
}
