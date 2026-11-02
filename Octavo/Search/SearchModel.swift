import Foundation
import Observation
import OctavoKit

/// The Search tab (`docs/design/direction.md`, Search tab, decision 21):
/// results update as you type, books from the server and the iPhone
/// together, then the server's series and authors. A server that can't
/// search finds only the books on the iPhone. Lives in the shell, so the
/// query and results outlast tab switches and folds.
@Observable
final class SearchModel {
    enum State: Equatable {
        /// Nothing to search for yet.
        case idle
        /// Waiting for the typing to pause, or for the server.
        case searching
        case loaded
        /// Something other than a connection problem, which shows as the
        /// banner instead (decision 22).
        case failed
    }

    struct Results: Equatable {
        var query: String
        /// The server's matches in its order, then the iPhone's it didn't
        /// send.
        var books: [SourcedBook]
        var series: [LibraryEntry]
        var authors: [LibraryEntry]
        /// Every matching book as a Library list, when there are more than
        /// Search shows.
        var allBooks: LibraryEntry?
        var source: LibrarySourceID
    }

    /// What's in the field. Setting it searches once the typing pauses.
    var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    /// The latest search's results, kept while the next one loads.
    private(set) var results: Results?
    private(set) var state = State.idle
    /// Newest first.
    private(set) var recentSearches: [String]

    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private let isOnIPhone: (LibraryBook) -> Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    /// BookOrbit refuses shorter queries.
    static let minimumLength = 2
    static let recentLimit = 8
    /// Books shown before "All 40 books".
    static let bookLimit = 12
    private static let recentKey = "recentSearches"

    init(
        library: LibraryModel, isOnIPhone: @escaping (LibraryBook) -> Bool,
        defaults: UserDefaults = .standard, pause: Duration = .milliseconds(300)
    ) {
        self.library = library
        self.isOnIPhone = isOnIPhone
        self.defaults = defaults
        self.pause = pause
        recentSearches = defaults.stringArray(forKey: Self.recentKey) ?? []
    }

    /// Whether the server searches. Without it, Search finds only the books
    /// on the iPhone and says so.
    var serverSearches: Bool {
        library.root?.search != .unavailable
    }

    /// What the results are for, once it's long enough to search.
    var searchText: String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count >= Self.minimumLength ? text : nil
    }

    /// Return in the field: searches now and remembers the search.
    func submit() {
        remember()
        guard let text = searchText else { return }
        start(text, after: .zero)
    }

    /// Try again after a failure.
    func retry() {
        guard let text = searchText else { return }
        start(text, after: .zero)
    }

    /// Keeps the search in Recent: on Return, or when a result is opened.
    func remember() {
        guard let text = searchText else { return }
        let others = recentSearches.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        recentSearches = Array(([text] + others).prefix(Self.recentLimit))
        defaults.set(recentSearches, forKey: Self.recentKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        defaults.removeObject(forKey: Self.recentKey)
    }

    /// Another server: its results go, the field empties.
    func reset() {
        task?.cancel()
        task = nil
        query = ""
        results = nil
        state = .idle
    }

    /// Waits for the typing to pause before searching; a new keystroke
    /// cancels the wait (and a search still loading).
    func waitForSearch() async {
        await task?.value
    }

    private func queryChanged() {
        guard let text = searchText else {
            task?.cancel()
            task = nil
            results = nil
            state = .idle
            return
        }
        start(text, after: pause)
    }

    private func start(_ text: String, after pause: Duration) {
        task?.cancel()
        state = .searching
        task = Task { [weak self] in
            if pause > .zero {
                try? await Task.sleep(for: pause)
            }
            guard !Task.isCancelled else { return }
            await self?.search(text)
        }
    }

    private func search(_ text: String) async {
        guard let server = library.server else { return }
        let local = library.iPhoneBooks().filter { isOnIPhone($0.book) && Self.matches($0.book, text) }
        guard serverSearches else {
            finish(Results(query: text, books: local, series: [], authors: [], source: server.id))
            return
        }
        do {
            let found = try await server.source.search(text)
            guard !Task.isCancelled else { return }
            finish(Self.results(found, from: server.id, adding: local, query: text))
        } catch {
            guard !Task.isCancelled else { return }
            library.report(error)
            // Offline, the books on the iPhone still match.
            finish(Results(query: text, books: local, series: [], authors: [], source: server.id),
                   failed: library.connectionProblem == nil)
        }
    }

    private func finish(_ results: Results, failed: Bool = false) {
        self.results = results
        state = failed ? .failed : .loaded
    }

    static func results(_ found: LibrarySearchResults, from source: LibrarySourceID, adding local: [SourcedBook], query: String) -> Results {
        let server = found.books.books.map { SourcedBook(source: source, book: $0) }
        let ids = Set(server.map(\.id))
        let books = server + local.filter { !ids.contains($0.id) }
        let more = found.books.next != nil || books.count > bookLimit
        let all = found.booksLink.flatMap { link in
            more ? LibraryEntry(kind: .feed, title: "“\(query)”", count: found.books.total, link: link) : nil
        }
        return Results(query: query, books: books, series: found.series, authors: found.authors, allBooks: all, source: source)
    }

    /// A book on the iPhone matches by its title, an author or its series.
    nonisolated static func matches(_ book: LibraryBook, _ text: String) -> Bool {
        book.title.localizedStandardContains(text)
            || book.authors.contains { $0.localizedStandardContains(text) }
            || book.series?.name.localizedStandardContains(text) == true
    }
}
