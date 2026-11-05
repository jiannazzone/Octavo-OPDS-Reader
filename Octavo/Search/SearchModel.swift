import Foundation
import Observation
import OctavoKit

/// The Search tab (`docs/design/direction.md`, Search tab, decisions 21 and
/// 36): results update as you type, books from the server and the iPhone
/// together, then the server's series and authors. A server that can't
/// search finds only the books on the iPhone. With several servers every one
/// is searched, each its own section that fills in when it answers. Lives in
/// the shell, so the query and results outlast tab switches and folds.
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

    /// One server's part of a search. With no server or one, the only one.
    struct Section: Equatable, Identifiable {
        var source: LibrarySourceID
        /// Its last results, kept while the next load.
        var results: Results?
        var state = State.searching

        var id: LibrarySourceID { source }
    }

    /// What's in the field. Setting it searches once the typing pauses.
    var query = "" {
        didSet { if query != oldValue { queryChanged() } }
    }
    /// Every server's, in the order they were added, then (with several) the
    /// imported books, under `LibrarySourceID.files`.
    private(set) var sections: [Section] = []
    /// The latest search's results with no server or one, kept while the next
    /// one loads.
    var results: Results? { sections.first?.results }
    /// Searching until every server has answered.
    private(set) var state = State.idle
    /// Newest first.
    private(set) var recentSearches: [String]

    @ObservationIgnored private let library: LibraryModel
    @ObservationIgnored private let isOnIPhone: (SourcedBook) -> Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    /// BookOrbit refuses shorter queries.
    static let minimumLength = 2
    static let recentLimit = 8
    /// Books shown before "All 40 books".
    static let bookLimit = 12
    /// The same in each section, with several servers: the next server stays
    /// in reach (decision 36).
    static let sectionBookLimit = 3
    private static let recentKey = "recentSearches"

    init(
        library: LibraryModel, isOnIPhone: @escaping (SourcedBook) -> Bool,
        defaults: UserDefaults = .standard, pause: Duration = .milliseconds(300)
    ) {
        self.library = library
        self.isOnIPhone = isOnIPhone
        self.defaults = defaults
        self.pause = pause
        recentSearches = defaults.stringArray(forKey: Self.recentKey) ?? []
    }

    /// Whether the Library's server searches. Without it, Search finds only
    /// the books on the iPhone and says so.
    var serverSearches: Bool {
        library.root?.search != .unavailable
    }

    /// How many of a section's books show.
    var bookLimit: Int {
        library.hasSeveralServers ? Self.sectionBookLimit : Self.bookLimit
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

    /// Try again in one server's section, which asks that server what else
    /// failed too.
    func retry(_ id: LibrarySourceID) {
        guard let text = searchText, let connection = library.connection(id) else { return }
        let local = localMatches(text, in: id)
        Task { [weak self] in
            await self?.library.retry(id)
            await self?.search(text, on: connection, adding: local)
        }
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

    /// A server came or went: the results go, the field empties.
    func reset() {
        task?.cancel()
        task = nil
        query = ""
        sections = []
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
            sections = []
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
        let connections = library.connections
        let imported = localMatches(text, in: .files)
        // No server yet: the imported books alone.
        guard !connections.isEmpty else {
            sections = [Section(source: .files, results: Results(query: text, books: imported, series: [], authors: [], source: .files), state: .loaded)]
            stateChanged()
            return
        }
        // Each keeps what it showed until its server answers. With one
        // server, the imported books are among its own.
        let several = connections.count > 1
        var next = connections.map { connection in
            var section = sections.first { $0.source == connection.server.id } ?? Section(source: connection.server.id)
            section.state = .searching
            return section
        }
        if several, !imported.isEmpty {
            next.append(Section(source: .files, results: Results(query: text, books: imported, series: [], authors: [], source: .files), state: .loaded))
        }
        sections = next
        stateChanged()
        await withTaskGroup(of: Void.self) { group in
            for connection in connections {
                let id = connection.server.id
                let local = localMatches(text, in: id) + (several ? [] : imported)
                group.addTask { await self.search(text, on: connection, adding: local) }
            }
        }
    }

    /// `id`'s books that are on the iPhone and match.
    private func localMatches(_ text: String, in id: LibrarySourceID) -> [SourcedBook] {
        library.iPhoneBooks().filter { $0.source == id && isOnIPhone($0) && Self.matches($0.book, text) }
    }

    private func search(_ text: String, on connection: ServerConnection, adding local: [SourcedBook]) async {
        let server = connection.server
        let listed = Results(query: text, books: local, series: [], authors: [], source: server.id)
        guard connection.root?.search != .unavailable else {
            finish(listed, for: server.id)
            return
        }
        do {
            let found = try await server.source.search(text)
            guard !Task.isCancelled else { return }
            finish(Self.results(found, from: server.id, adding: local, query: text, limit: bookLimit), for: server.id)
        } catch {
            guard !Task.isCancelled else { return }
            library.report(error, server: server.id)
            // Offline, the books on the iPhone still match.
            finish(listed, for: server.id, failed: connection.problem == nil)
        }
    }

    private func finish(_ results: Results, for id: LibrarySourceID, failed: Bool = false) {
        guard let index = sections.firstIndex(where: { $0.source == id }) else { return }
        sections[index].results = results
        sections[index].state = failed ? .failed : .loaded
        stateChanged()
    }

    private func stateChanged() {
        if sections.contains(where: { $0.state == .searching }) {
            state = .searching
        } else {
            state = sections.contains { $0.state == .failed } ? .failed : .loaded
        }
    }

    static func results(
        _ found: LibrarySearchResults, from source: LibrarySourceID, adding local: [SourcedBook], query: String, limit: Int = bookLimit
    ) -> Results {
        let server = found.books.books.map { SourcedBook(source: source, book: $0) }
        let ids = Set(server.map(\.id))
        let books = server + local.filter { !ids.contains($0.id) }
        let more = found.books.next != nil || books.count > limit
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
