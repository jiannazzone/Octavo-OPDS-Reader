import Foundation
import Observation
import OctavoKit

/// One list from a library (a chip, a collection, a series, an author, an
/// OPDS feed), loaded a page at a time. `LibraryModel` keeps one per link, so
/// folding, which rebuilds the views, doesn't load it again.
@Observable
final class FeedModel {
    enum State: Equatable {
        case idle, loading, loaded
        /// Something other than a connection problem, which shows as the
        /// tab's banner instead (decision 22).
        case failed
    }

    let link: LibraryLink
    let source: LibrarySourceID
    private(set) var title: String?
    private(set) var entries: [LibraryEntry] = []
    private(set) var books: [LibraryBook] = []
    /// Items across all pages, if the library knows.
    private(set) var total: Int?
    private(set) var state = State.idle
    private(set) var hasMore = false
    /// Authors A–Z, grouped once per page rather than on every redraw.
    /// Empty unless the list is only authors.
    private(set) var authorSections: [AuthorIndex.Section] = []
    /// The first page had nothing on it (`EmptyFeed`). Stays set through a
    /// reload, so pulling down doesn't swap the screen for blank covers, and
    /// through one that fails, which `EmptyFeed` says itself.
    private(set) var cameBackEmpty = false
    /// The source stopped reading the list after this many books (a
    /// filtered series or author, #131).
    private(set) var loadedOnly: Int?

    @ObservationIgnored private let library: any LibrarySource
    @ObservationIgnored private let report: (any Error) -> Void
    /// A page arrived, with the server's latest word on its books.
    @ObservationIgnored private let listed: ([LibraryBook]) -> Void
    @ObservationIgnored private var next: LibraryLink?
    /// The pages loaded so far: a server whose next page is one of these is
    /// looping, and the list ends there.
    @ObservationIgnored private var fetched: Set<LibraryLink> = []
    @ObservationIgnored private var task: Task<Void, Never>?

    /// The most `loadAll` follows. The server decides how many pages there
    /// are, so a list that never ends stops here.
    static let maxPagesToLoadAll = 100

    init(
        link: LibraryLink, source: LibrarySourceID, library: any LibrarySource, report: @escaping (any Error) -> Void,
        listed: @escaping ([LibraryBook]) -> Void = { _ in }
    ) {
        self.link = link
        self.source = source
        self.library = library
        self.report = report
        self.listed = listed
    }

    /// The first page, unless it's loaded or loading (then this waits for it).
    func load() async {
        guard state == .idle || state == .failed else {
            if let task { await task.value }
            return
        }
        await run(reset: true, link)
    }

    /// The first page again, keeping what's shown until it arrives.
    func reload() async {
        task?.cancel()
        await run(reset: true, link)
    }

    /// The next page, if there is one and nothing else is loading.
    func loadMore() async {
        guard state == .loaded, let next else { return }
        await run(reset: false, next)
    }

    /// After a failure: the page that failed, or the first if nothing loaded.
    func retry() async {
        if next != nil, !(entries.isEmpty && books.isEmpty) {
            state = .loaded
            await loadMore()
        } else {
            await reload()
        }
    }

    /// Every page, for lists that flow from one page of the spread onto the
    /// next or jump around (Authors A–Z), up to `maxPages`.
    func loadAll(maxPages: Int = FeedModel.maxPagesToLoadAll) async {
        await load()
        var pages = 1
        while state == .loaded, hasMore, pages < maxPages, !Task.isCancelled {
            await loadMore()
            pages += 1
        }
    }

    /// Every page until `maxBooks` books, for a list sorted or filtered on
    /// the iPhone (#131). `hasMore` afterwards: it stopped at the cap.
    func loadAll(maxBooks: Int) async {
        await load()
        while state == .loaded, hasMore, books.count < maxBooks, !Task.isCancelled {
            let before = books.count
            await loadMore()
            // A page with no books on it: the server's paging went wrong.
            if books.count == before { break }
        }
    }

    /// Whether `loadAll(maxBooks:)` stopped at its cap with more to come, not
    /// at a page that went wrong.
    func isCapped(at maxBooks: Int) -> Bool {
        hasMore && books.count >= maxBooks
    }

    /// Every page has loaded, or as many as `loadAll(maxBooks:)` takes.
    func isWhole(upTo maxBooks: Int) -> Bool {
        state == .loaded && (!hasMore || books.count >= maxBooks)
    }

    /// The most books a list sorted or filtered on the iPhone loads (Adam,
    /// 2026-11-09). From 0.4 to 5 s on this Mac at 2,000
    /// (`docs/notes/library-filters.md`).
    static let maxBooksToArrange = 2_000

    private func run(reset: Bool, _ page: LibraryLink) async {
        state = .loading
        let task = Task {
            do {
                let feed = try await library.feed(page)
                try Task.checkCancellation()
                apply(feed, page: page, reset: reset)
            } catch {
                // A reload took over.
                guard !Task.isCancelled else { return }
                state = .failed
                report(error)
            }
        }
        self.task = task
        await task.value
    }

    private func apply(_ feed: LibraryFeed, page: LibraryLink, reset: Bool) {
        if reset { fetched = [] }
        fetched.insert(page)
        if reset {
            title = feed.title
            entries = feed.entries
            books = feed.books
            cameBackEmpty = feed.entries.isEmpty && feed.books.isEmpty
            loadedOnly = feed.loadedOnly
        } else {
            entries += feed.entries
            books += feed.books
        }
        authorSections = isAuthorList ? AuthorIndex.sections(entries) : []
        total = feed.total ?? total
        next = feed.next.flatMap { fetched.contains($0) ? nil : $0 }
        hasMore = next != nil
        state = .loaded
        listed(feed.books)
    }
}

extension FeedModel {
    /// Only authors: shown A–Z with an index strip.
    var isAuthorList: Bool {
        books.isEmpty && !entries.isEmpty && entries.allSatisfy { $0.kind == .author }
    }

    /// Only series: shown as a grid of cover stacks.
    var isSeriesList: Bool {
        books.isEmpty && !entries.isEmpty && entries.allSatisfy { $0.kind == .series }
    }
}
