import Foundation
import OctavoKit
import Synchronization
import Testing
@testable import Octavo

/// A server whose search answers from a fixed list, or fails, and remembers
/// what it was asked.
private nonisolated final class SearchSource: LibrarySource, Sendable {
    let support: LibrarySearchSupport
    private let state: Mutex<(results: LibrarySearchResults?, error: (any Error & Sendable)?, queries: [String])>

    init(support: LibrarySearchSupport = .booksSeriesAndAuthors, results: LibrarySearchResults? = nil) {
        self.support = support
        state = Mutex((results, nil, []))
    }

    var queries: [String] { state.withLock { $0.queries } }
    func fail(with error: (any Error & Sendable)?) { state.withLock { $0.error = error } }

    func root() async throws -> LibraryRoot {
        LibraryRoot(chips: [LibraryEntry(kind: .feed, title: "All", link: LibraryLink(rawValue: "all"))], search: support)
    }

    func feed(_ link: LibraryLink) async throws -> LibraryFeed { LibraryFeed() }

    func search(_ query: String) async throws -> LibrarySearchResults {
        let (results, error) = state.withLock { state in
            state.queries.append(query)
            return (state.results, state.error)
        }
        if let error { throw error }
        return results ?? LibrarySearchResults(query: query)
    }

    func details(for book: LibraryBook) async throws -> LibraryBookDetails { LibraryBookDetails(book: book) }
    func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data { throw LibraryError.notFound }
    func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        throw LibraryError.notFound
    }
}

private let server = LibrarySourceID(rawValue: "server")

private func book(_ id: String, _ title: String, by author: String = "Someone") -> LibraryBook {
    LibraryBook(id: LibraryBookID(rawValue: id), title: title, authors: [author])
}

private func temporaryFile(_ name: String) -> URL {
    URL.testDirectory.appending(path: "\(name)-\(UUID().uuidString).json")
}

@MainActor
private struct Harness {
    let library: LibraryModel
    let search: SearchModel
    let defaults: UserDefaults

    /// `downloaded`: the books whose files are on the iPhone.
    init(_ source: SearchSource, downloaded: Set<String> = [], pause: Duration = .zero) async {
        library = LibraryModel(
            recents: RecentBooks(fileURL: temporaryFile("RecentBooks")),
            finished: FinishedBooks(fileURL: temporaryFile("FinishedBooks")),
            onIPhone: BooksOnIPhone(fileURL: temporaryFile("BooksOnIPhone")), imported: .temporary()
        )
        defaults = UserDefaults.testSuite("SearchModelTests")
        search = SearchModel(library: library, isOnIPhone: { downloaded.contains($0.id.rawValue) }, defaults: defaults, pause: pause)
        await library.connect(LibraryServer(id: server, name: "Calibre-Web", source: source))
    }

    func type(_ query: String) async {
        search.query = query
        await search.waitForSearch()
    }
}

@MainActor
@Suite(.temporaryFiles)
struct SearchModelTests {
    @Test func resultsArriveOnceTheTypingPauses() async {
        let found = LibrarySearchResults(
            query: "wells", books: LibraryFeed(books: [book("1", "The Time Machine", by: "H. G. Wells")]),
            authors: [LibraryEntry(kind: .author, title: "H. G. Wells", link: LibraryLink(rawValue: "authors/1"))]
        )
        let harness = await Harness(SearchSource(results: found), pause: .milliseconds(10))
        harness.search.query = "wells"
        #expect(harness.search.state == .searching)
        await harness.search.waitForSearch()
        #expect(harness.search.state == .loaded)
        #expect(harness.search.results?.books.map(\.book.title) == ["The Time Machine"])
        #expect(harness.search.results?.authors.map(\.title) == ["H. G. Wells"])
        #expect(harness.search.results?.allBooks == nil, "nothing more to show")
    }

    @Test func aNewKeystrokeReplacesTheWaitingSearch() async {
        let source = SearchSource()
        let harness = await Harness(source, pause: .milliseconds(50))
        harness.search.query = "we"
        harness.search.query = "wel"
        await harness.search.waitForSearch()
        #expect(source.queries == ["wel"])
    }

    @Test func oneLetterDoesntSearch() async {
        let source = SearchSource()
        let harness = await Harness(source)
        await harness.type(" w ")
        #expect(harness.search.state == .idle)
        #expect(harness.search.searchText == nil)
        #expect(source.queries.isEmpty)
    }

    @Test func booksOnTheIPhoneJoinTheServersMatches() async {
        let onServer = book("1", "The Time Machine", by: "H. G. Wells")
        let source = SearchSource(results: LibrarySearchResults(query: "time", books: LibraryFeed(books: [onServer])))
        let harness = await Harness(source, downloaded: ["1", "2"])
        harness.library.bookDownloading(SourcedBook(source: server, book: onServer))
        harness.library.bookDownloading(SourcedBook(source: server, book: book("2", "Time and Again")))
        harness.library.bookDownloading(SourcedBook(source: server, book: book("3", "Times Past")))
        harness.library.bookDownloading(SourcedBook(source: LibrarySourceID(rawValue: "other"), book: book("2", "Time Out")))
        await harness.type("time")
        // Once each; not "Times Past", which isn't downloaded, nor another
        // server's book.
        #expect(harness.search.results?.books.map(\.book.title) == ["The Time Machine", "Time and Again"])
    }

    @Test func aServerWithoutSearchFindsOnlyTheIPhonesBooks() async {
        let source = SearchSource(support: .unavailable)
        let harness = await Harness(source, downloaded: ["2"])
        harness.library.bookDownloading(SourcedBook(source: server, book: book("2", "Kidnapped", by: "R. L. Stevenson")))
        #expect(!harness.search.serverSearches)
        await harness.type("stevenson")
        #expect(harness.search.results?.books.map(\.book.title) == ["Kidnapped"])
        #expect(source.queries.isEmpty)
    }

    @Test func offlineTheIPhonesBooksStillMatch() async {
        let source = SearchSource()
        source.fail(with: URLError(.notConnectedToInternet))
        let harness = await Harness(source, downloaded: ["2"])
        harness.library.bookDownloading(SourcedBook(source: server, book: book("2", "Kidnapped")))
        await harness.type("kidnap")
        #expect(harness.search.state == .loaded, "the banner says why")
        #expect(harness.library.connectionProblem == .unreachable(server: "Calibre-Web"))
        #expect(harness.search.results?.books.map(\.book.title) == ["Kidnapped"])
    }

    @Test func aServerErrorShowsAsAFailure() async {
        let source = SearchSource()
        source.fail(with: LibraryError.server(status: 500, message: nil))
        let harness = await Harness(source)
        await harness.type("kidnap")
        #expect(harness.search.state == .failed)
        #expect(harness.library.connectionProblem == nil)

        source.fail(with: nil)
        harness.search.retry()
        await harness.search.waitForSearch()
        #expect(harness.search.state == .loaded)
    }

    @Test func moreBooksThanSearchShowsLeadToTheFullList() async {
        let all = LibraryLink(rawValue: "search?q=the")
        let books = (1...20).map { book("\($0)", "The \($0)") }
        let paged = LibrarySearchResults(
            query: "the", books: LibraryFeed(books: books, total: 134, next: LibraryLink(rawValue: "search?q=the&page=2")), booksLink: all
        )
        let harness = await Harness(SearchSource(results: paged))
        await harness.type("the")
        let entry = harness.search.results?.allBooks
        #expect(entry?.link == all)
        #expect(entry?.count == 134)
        #expect(entry?.title == "“the”")

        let few = SearchModel.results(
            LibrarySearchResults(query: "the", books: LibraryFeed(books: Array(books.prefix(SearchModel.bookLimit))), booksLink: all),
            from: server, adding: [], query: "the"
        )
        #expect(few.allBooks == nil)
        let many = SearchModel.results(
            LibrarySearchResults(query: "the", books: LibraryFeed(books: Array(books.prefix(SearchModel.bookLimit + 1))), booksLink: all),
            from: server, adding: [], query: "the"
        )
        #expect(many.allBooks?.count == nil, "the server didn't say how many")
    }

    @Test func recentSearchesKeepTheNewestOnceEach() async {
        let harness = await Harness(SearchSource())
        for query in ["wells", "austen", "Wells"] {
            harness.search.query = query
            harness.search.remember()
        }
        #expect(harness.search.recentSearches == ["Wells", "austen"])
        for index in 0..<10 {
            harness.search.query = "query \(index)"
            harness.search.remember()
        }
        #expect(harness.search.recentSearches.count == SearchModel.recentLimit)
        #expect(harness.search.recentSearches.first == "query 9")

        let reopened = SearchModel(library: harness.library, isOnIPhone: { _ in false }, defaults: harness.defaults)
        #expect(reopened.recentSearches == harness.search.recentSearches)

        harness.search.clearRecentSearches()
        #expect(harness.search.recentSearches.isEmpty)
        #expect(SearchModel(library: harness.library, isOnIPhone: { _ in false }, defaults: harness.defaults).recentSearches.isEmpty)
    }

    @Test func submittingRemembersAndSearchesAtOnce() async {
        let source = SearchSource()
        let harness = await Harness(source, pause: .seconds(60))
        harness.search.query = "  wells "
        harness.search.submit()
        await harness.search.waitForSearch()
        #expect(source.queries == ["wells"])
        #expect(harness.search.recentSearches == ["wells"])
    }

    @Test func aMatchIsByTitleAuthorOrSeries() {
        var kidnapped = book("1", "Kidnapped", by: "Robert Louis Stevenson")
        kidnapped.series = LibrarySeriesPosition(name: "Balfour", position: 1)
        #expect(SearchModel.matches(kidnapped, "kidnap"))
        #expect(SearchModel.matches(kidnapped, "louis"))
        #expect(SearchModel.matches(kidnapped, "balf"))
        #expect(!SearchModel.matches(kidnapped, "treasure"))
    }
}

@MainActor
@Suite(.temporaryFiles)
struct BooksOnIPhoneTests {
    @Test func keepsTheNewestFirstOnceEach() throws {
        let store = BooksOnIPhone(fileURL: temporaryFile("BooksOnIPhone"))
        let first = SourcedBook(source: server, book: book("1", "One"))
        let second = SourcedBook(source: server, book: book("2", "Two"))
        try store.record(first)
        try store.record(second)
        try store.record(first)
        #expect(store.books().map(\.book.title) == ["One", "Two"])
        try store.remove(first.id)
        #expect(store.books().map(\.book.title) == ["Two"])
    }

    @Test func theLibraryAddsBooksOpenedBeforeTheListExisted() async throws {
        let recents = RecentBooks(fileURL: temporaryFile("RecentBooks"))
        try recents.record(SourcedBook(source: server, book: book("1", "Opened long ago")))
        let library = LibraryModel(
            recents: recents, finished: FinishedBooks(fileURL: temporaryFile("FinishedBooks")),
            onIPhone: BooksOnIPhone(fileURL: temporaryFile("BooksOnIPhone")), imported: .temporary()
        )
        await library.connect(LibraryServer(id: server, name: "Shelf", source: SearchSource()))
        library.bookDownloading(SourcedBook(source: server, book: book("2", "Downloaded")))
        library.bookDownloading(SourcedBook(source: server, book: book("1", "Opened long ago")))
        #expect(library.iPhoneBooks().map(\.book.title) == ["Opened long ago", "Downloaded"])
    }
}
