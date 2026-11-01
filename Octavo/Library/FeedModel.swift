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

    @ObservationIgnored private let library: any LibrarySource
    @ObservationIgnored private let report: (any Error) -> Void
    @ObservationIgnored private var next: LibraryLink?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(link: LibraryLink, source: LibrarySourceID, library: any LibrarySource, report: @escaping (any Error) -> Void) {
        self.link = link
        self.source = source
        self.library = library
        self.report = report
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

    /// Every page, for lists that jump around (Authors A–Z).
    func loadAll() async {
        await load()
        while state == .loaded, hasMore, !Task.isCancelled {
            await loadMore()
        }
    }

    private func run(reset: Bool, _ page: LibraryLink) async {
        state = .loading
        let task = Task {
            do {
                let feed = try await library.feed(page)
                try Task.checkCancellation()
                apply(feed, reset: reset)
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

    private func apply(_ feed: LibraryFeed, reset: Bool) {
        if reset {
            title = feed.title
            entries = feed.entries
            books = feed.books
        } else {
            entries += feed.entries
            books += feed.books
        }
        total = feed.total ?? total
        next = feed.next
        hasMore = feed.next != nil
        state = .loaded
    }
}
