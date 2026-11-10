import Foundation

/// A BookOrbit server as a `LibrarySource`.
///
/// The chips are All, Collections (with smart scopes), Series and Authors,
/// with Recently added and Unread as shelves.
/// Lists span every library the user can see; podcast collections and scopes
/// are left out. Search covers books, series and authors.
public struct BookOrbitSource: LibrarySource {
    public let client: BookOrbitClient
    /// Items per page, 1–100 (BookOrbit's limit for series and authors).
    public let pageSize: Int
    /// Whether books carry the server's reading progress. Off when the
    /// iPhone keeps its own place (setup's "Don't sync"), so no screen shows
    /// a place the book won't open at.
    public let includesProgress: Bool

    public init(client: BookOrbitClient, pageSize: Int = 50, includesProgress: Bool = true) {
        self.client = client
        self.pageSize = min(max(pageSize, 1), 100)
        self.includesProgress = includesProgress
    }

    /// The BookOrbit file id behind `file`, for `BookOrbitProgressSync`.
    public static func fileID(of file: LibraryFile) -> Int? {
        Int(file.id.rawValue)
    }

    public func root() async throws -> LibraryRoot {
        LibraryRoot(
            title: "BookOrbit",
            chips: [
                LibraryEntry(kind: .feed, title: "All", link: BookOrbitRoute.books(page: 0).link),
                LibraryEntry(kind: .feed, title: "Collections", link: BookOrbitRoute.collections.link),
                LibraryEntry(kind: .feed, title: "Series", link: BookOrbitRoute.seriesList(page: 0).link),
                LibraryEntry(kind: .feed, title: "Authors", link: BookOrbitRoute.authors(page: 0).link),
            ],
            search: .booksSeriesAndAuthors,
            recentlyAdded: BookOrbitRoute.recent(page: 0).link,
            unread: BookOrbitRoute.books(page: 0, filter: .unread).link,
            continueReading: BookOrbitRoute.continueReading.link
        )
    }

    public func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        guard let route = BookOrbitRoute(link) else { throw LibraryError.invalidLink }
        return try await mappingErrors {
            switch route {
            case .books(let page, let sort, let filter):
                return bookFeed(
                    try await client.books(filter: filter.bookOrbit, sort: [sort.bookOrbit], page: page, size: pageSize), title: "All", page: page
                ) { .books(page: $0, sort: sort, filter: filter) }
            case .recent(let page, let filter):
                return bookFeed(
                    try await client.books(filter: filter.bookOrbit, sort: [.newest], page: page, size: pageSize), page: page
                ) { .recent(page: $0, filter: filter) }
            case .continueReading:
                // One page: BookOrbit caps the list (its own home shows 20)
                // rather than paging it.
                let books = try await client.continueReading(limit: 20).map(listed)
                return LibraryFeed(title: "Continue reading", books: books, total: books.count)
            case .collections:
                async let collections = client.collections()
                async let scopes = client.smartScopes()
                let entries = try await collections.filter(\.holdsBooks).map(entry)
                    + (try await scopes).filter(\.holdsBooks).map(entry)
                return LibraryFeed(title: "Collections", entries: entries, total: entries.count)
            case .collection(let id, let page, let sort, let filter):
                return bookFeed(
                    try await client.collectionBooks(collectionID: id, filter: filter.bookOrbit, sort: [sort.bookOrbit], page: page, size: pageSize),
                    page: page
                ) { .collection(id: id, page: $0, sort: sort, filter: filter) }
            case .smartScope(let id, let page, let sort, let filter):
                return bookFeed(
                    try await client.smartScopeBooks(scopeID: id, filter: filter.bookOrbit, sort: [sort.bookOrbit], page: page, size: pageSize),
                    page: page
                ) { .smartScope(id: id, page: $0, sort: sort, filter: filter) }
            case .seriesList(let page):
                let series = try await client.series(page: page, size: pageSize)
                return LibraryFeed(title: "Series", entries: series.items.map(entry), total: series.total,
                                   next: next(after: page, of: series) { .seriesList(page: $0) })
            case .series(let id, let page, let sort, .all):
                return bookFeed(
                    try await client.seriesBooks(seriesID: id, sort: sort.bookOrbit, page: page, size: pageSize), page: page
                ) { .series(id: id, page: $0, sort: sort) }
            case .series(let id, _, let sort, let filter):
                return try await filtered(filter) { try await client.seriesBooks(seriesID: id, sort: sort.bookOrbit, page: $0, size: $1) }
            case .authors(let page):
                let authors = try await client.authors(page: page, size: pageSize)
                return LibraryFeed(title: "Authors", entries: authors.items.map(entry), total: authors.total,
                                   next: next(after: page, of: authors) { .authors(page: $0) })
            case .author(let id, let page, let sort, .all):
                return bookFeed(
                    try await client.authorBooks(authorID: id, sort: sort.bookOrbit, page: page, size: pageSize), page: page
                ) { .author(id: id, page: $0, sort: sort) }
            case .author(let id, _, let sort, let filter):
                return try await filtered(filter) { try await client.authorBooks(authorID: id, sort: sort.bookOrbit, page: $0, size: $1) }
            case .search(let query, let page):
                return try await searchFeed(query, page: page)
            }
        }
    }

    public func search(_ query: String) async throws -> LibrarySearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // BookOrbit rejects shorter queries.
        guard query.count >= 2 else { return LibrarySearchResults(query: query) }
        return try await mappingErrors {
            // Books come from `books/query` so that `next` pages on in the
            // same order; `search` supplies the series and author matches.
            async let books = searchFeed(query, page: 0)
            async let matches = client.search(query)
            return LibrarySearchResults(
                query: query,
                books: try await books,
                booksLink: BookOrbitRoute.search(query: query, page: 0).link,
                series: try await matches.series.map(entry),
                authors: try await matches.authors.map(entry)
            )
        }
    }

    public func order(of link: LibraryLink) -> LibraryListOrder? {
        guard let route = BookOrbitRoute(link), let order = route.order else { return nil }
        return LibraryListOrder(
            sorts: route.sorts, filters: LibraryFilter.allCases, sort: order.sort, filter: order.filter,
            takesRememberedSort: route.takesRememberedSort
        )
    }

    public func link(_ link: LibraryLink, sortedBy sort: LibrarySort?, showing filter: LibraryFilter) -> LibraryLink {
        BookOrbitRoute(link)?.ordered(sort, filter).link ?? link
    }

    public var tracksFinished: Bool { true }

    /// Finished is BookOrbit's `read`; not finished goes back to `reading`.
    public func setFinished(_ finished: Bool, for book: LibraryBook) async throws {
        guard let id = Int(book.id.rawValue) else { throw LibraryError.invalidLink }
        try await client.setReadStatus(finished ? "read" : "reading", bookID: id)
    }

    public func details(for book: LibraryBook) async throws -> LibraryBookDetails {
        guard let id = Int(book.id.rawValue) else { throw LibraryError.invalidLink }
        let detail = try await mappingErrors { try await client.book(id: id) }
        var summary = listed(detail)
        // The detail has no reading progress; keep the list's.
        summary.progress = summary.progress ?? book.progress
        let authors = detail.authorRefs.map { author in
            LibraryEntry(
                kind: .author,
                title: author.name,
                sortName: author.sortName,
                link: author.id.map { BookOrbitRoute.author(id: $0, page: 0) }?.link ?? BookOrbitRoute.search(query: author.name, page: 0).link
            )
        }
        var series = detail.seriesMemberships.map {
            LibrarySeriesPosition(name: $0.seriesName, position: $0.seriesIndex, link: BookOrbitRoute.series(id: $0.seriesID, page: 0).link)
        }
        if series.isEmpty, let only = summary.series { series = [only] }
        return LibraryBookDetails(
            book: summary,
            subtitle: detail.subtitle,
            description: detail.description,
            publisher: detail.publisher,
            language: detail.language,
            published: detail.publishedDate ?? detail.publishedYear.map(String.init),
            addedAt: detail.addedAt,
            authors: authors,
            series: series,
            collections: detail.collections.map {
                LibraryEntry(kind: .collection, title: $0.name, link: BookOrbitRoute.collection(id: $0.id, page: 0).link)
            }
        )
    }

    public func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data {
        if let authorID = Self.portraitAuthorID(cover) {
            return try await mappingErrors { try await client.authorThumbnail(authorID: authorID) }
        }
        guard let bookID = Self.coverBookID(cover) else { throw LibraryError.invalidLink }
        return try await mappingErrors { try await client.cover(bookID: bookID, thumbnail: size == .thumbnail) }
    }

    @discardableResult
    public func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let fileID = Self.fileID(of: file) else { throw LibraryError.invalidLink }
        return try await mappingErrors { try await client.download(fileID: fileID, to: destination, progress: progress) }
    }

    // MARK: - Mapping

    private func searchFeed(_ query: String, page: Int) async throws -> LibraryFeed {
        bookFeed(try await client.books(matching: query, sort: [.relevance], page: page, size: pageSize), page: page) {
            .search(query: query, page: $0)
        }
    }

    /// Every page of a list that `books/query` can't filter (a series', an
    /// author's books), keeping what `filter` shows: one page, up to
    /// `maxFilteredBooks`. `books/query` matches an author by any part of
    /// the name ("Dumas"), so it can't stand in (`docs/notes/library-filters.md`).
    private func filtered(
        _ filter: LibraryFilter, _ fetch: (_ page: Int, _ size: Int) async throws -> BookOrbitPage<BookOrbitBook>
    ) async throws -> LibraryFeed {
        let size = 100
        var books: [LibraryBook] = []
        for page in 0..<(Self.maxFilteredBooks / size) {
            let result = try await fetch(page, size)
            books += result.items.filter(filter.matches).map(listed)
            if result.items.count < size || (page + 1) * size >= result.total ?? .max { break }
        }
        return LibraryFeed(books: books, total: books.count)
    }

    /// The most books a filtered series or author list reads.
    static let maxFilteredBooks = 2_000

    private func bookFeed(
        _ page: BookOrbitPage<BookOrbitBook>, title: String? = nil, page number: Int,
        route: (Int) -> BookOrbitRoute
    ) -> LibraryFeed {
        LibraryFeed(title: title, books: page.items.map(listed), total: page.total, next: next(after: number, of: page, route))
    }

    /// The next page's link, or `nil` on the last page.
    private func next<Item>(after page: Int, of result: BookOrbitPage<Item>, _ route: (Int) -> BookOrbitRoute) -> LibraryLink? {
        let isLast = if let total = result.total {
            (page + 1) * pageSize >= total
        } else {
            result.items.count < pageSize
        }
        return isLast || result.items.isEmpty ? nil : route(page + 1).link
    }

    /// `book` as this source lists it: without the server's progress unless
    /// `includesProgress`.
    private func listed(_ book: BookOrbitBook) -> LibraryBook {
        var listed = Self.book(book)
        if !includesProgress { listed.progress = nil }
        return listed
    }

    static func book(_ book: BookOrbitBook) -> LibraryBook {
        LibraryBook(
            id: LibraryBookID(rawValue: String(book.id)),
            title: book.title,
            authors: book.authors,
            series: book.seriesName.map {
                LibrarySeriesPosition(name: $0, position: book.seriesIndex, link: book.seriesID.map { BookOrbitRoute.series(id: $0, page: 0).link })
            },
            cover: book.hasCover == false ? nil : cover(bookID: book.id, version: book.coverVersion),
            files: book.files.map {
                LibraryFile(id: LibraryFileID(rawValue: String($0.id)), format: $0.format, sizeBytes: $0.sizeBytes,
                            filename: $0.filename, isPrimary: $0.role == "primary")
            },
            progress: book.readingFraction,
            lastReadAt: book.readStatusUpdatedAt,
            isFinished: book.readStatus.map { $0 == "read" }
        )
    }

    private func entry(_ collection: BookOrbitCollection) -> LibraryEntry {
        LibraryEntry(kind: .collection, title: collection.name, subtitle: collection.description, count: collection.bookCount,
                     link: BookOrbitRoute.collection(id: collection.id, page: 0).link)
    }

    private func entry(_ scope: BookOrbitSmartScope) -> LibraryEntry {
        LibraryEntry(kind: .smartCollection, title: scope.name, count: scope.bookCount,
                     link: BookOrbitRoute.smartScope(id: scope.id, page: 0).link)
    }

    private func entry(_ series: BookOrbitSeries) -> LibraryEntry {
        LibraryEntry(
            kind: .series,
            title: series.name,
            subtitle: series.authors.isEmpty ? nil : series.authors.joined(separator: ", "),
            count: series.bookCount,
            previewCovers: series.coverBookIDs.prefix(3).map { Self.cover(bookID: $0, version: nil) },
            link: BookOrbitRoute.series(id: series.id, page: 0).link
        )
    }

    private func entry(_ author: BookOrbitAuthor) -> LibraryEntry {
        LibraryEntry(
            kind: .author,
            title: author.name,
            count: author.bookCount,
            sortName: author.sortName,
            previewCovers: author.coverBookID.map { [Self.cover(bookID: $0, version: nil)] } ?? [],
            portrait: author.imageURL.map { Self.portrait(authorID: author.id, imageURL: $0) },
            link: BookOrbitRoute.author(id: author.id, page: 0).link
        )
    }

    private static func cover(bookID: Int, version: String?) -> LibraryCover {
        LibraryCover(rawValue: "books/\(bookID)", version: version)
    }

    /// An author's photo, versioned by the server's `t=` so a new photo
    /// isn't served from the cache.
    static func portrait(authorID: Int, imageURL: String) -> LibraryCover {
        let version = URLComponents(string: imageURL)?.queryItems?.first { $0.name == "t" }?.value
        return LibraryCover(rawValue: "authors/\(authorID)", version: version)
    }

    private static func portraitAuthorID(_ cover: LibraryCover) -> Int? {
        guard cover.rawValue.hasPrefix("authors/") else { return nil }
        return Int(cover.rawValue.dropFirst("authors/".count))
    }

    private static func coverBookID(_ cover: LibraryCover) -> Int? {
        guard cover.rawValue.hasPrefix("books/") else { return nil }
        return Int(cover.rawValue.dropFirst("books/".count))
    }

    private func mappingErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as BookOrbitError {
            throw Self.libraryError(error)
        }
    }

    static func libraryError(_ error: BookOrbitError) -> LibraryError {
        switch error {
        case .notSignedIn, .sessionExpired: .signedOut
        case .http(status: 404, _): .notFound
        case .http(let status, let message): .server(status: status, message: message)
        case .invalidResponse: .invalidResponse
        }
    }
}

private extension BookOrbitCollection {
    var holdsBooks: Bool { mediaType != "podcasts" }
}

private extension BookOrbitSmartScope {
    var holdsBooks: Bool { mediaType != "podcasts" }
}

/// What a BookOrbit `LibraryLink` points at, written as a relative URL
/// (`collections/1?page=2&sort=author&show=unread`). A list's sort and filter
/// are written only when they aren't its own.
enum BookOrbitRoute: Hashable, Sendable {
    case books(page: Int, sort: LibrarySort = .title, filter: LibraryFilter = .all)
    case recent(page: Int, filter: LibraryFilter = .all)
    case continueReading
    case collections
    case collection(id: Int, page: Int, sort: LibrarySort = .title, filter: LibraryFilter = .all)
    case smartScope(id: Int, page: Int, sort: LibrarySort = .title, filter: LibraryFilter = .all)
    case seriesList(page: Int)
    case series(id: Int, page: Int, sort: LibrarySort = .readingOrder, filter: LibraryFilter = .all)
    case authors(page: Int)
    case author(id: Int, page: Int, sort: LibrarySort = .title, filter: LibraryFilter = .all)
    case search(query: String, page: Int)

    /// The sorts a list of books offers, its own first.
    var sorts: [LibrarySort] {
        switch self {
        case .books, .collection, .smartScope: [.title, .author, .recentlyAdded]
        case .series: [.readingOrder, .title, .recentlyAdded]
        case .author: [.title, .recentlyAdded]
        case .recent, .continueReading, .collections, .seriesList, .authors, .search: []
        }
    }

    /// Whether the list opens in the sort remembered for the server; a
    /// series' or an author's opens in its own.
    var takesRememberedSort: Bool {
        switch self {
        case .books, .collection, .smartScope: true
        default: false
        }
    }

    /// A list of books' sort and filter. `nil` for the rest.
    var order: (sort: LibrarySort?, filter: LibraryFilter)? {
        switch self {
        case .books(_, let sort, let filter), .collection(_, _, let sort, let filter), .smartScope(_, _, let sort, let filter),
             .series(_, _, let sort, let filter), .author(_, _, let sort, let filter):
            (sort, filter)
        case .recent(_, let filter): (nil, filter)
        case .continueReading, .collections, .seriesList, .authors, .search: nil
        }
    }

    /// The same list from the top, sorted by `sort` (if it offers it, else
    /// its own) and showing `filter`.
    func ordered(_ sort: LibrarySort?, _ filter: LibraryFilter) -> BookOrbitRoute {
        let sort = sort.flatMap { sorts.contains($0) ? $0 : nil } ?? sorts.first ?? .title
        return switch self {
        case .books: .books(page: 0, sort: sort, filter: filter)
        case .recent: .recent(page: 0, filter: filter)
        case .collection(let id, _, _, _): .collection(id: id, page: 0, sort: sort, filter: filter)
        case .smartScope(let id, _, _, _): .smartScope(id: id, page: 0, sort: sort, filter: filter)
        case .series(let id, _, _, _): .series(id: id, page: 0, sort: sort, filter: filter)
        case .author(let id, _, _, _): .author(id: id, page: 0, sort: sort, filter: filter)
        case .continueReading, .collections, .seriesList, .authors, .search: self
        }
    }

    var link: LibraryLink {
        var components = URLComponents()
        var query: [URLQueryItem] = []
        func paged(_ path: String, _ page: Int) {
            components.path = path
            query.append(URLQueryItem(name: "page", value: String(page)))
        }
        switch self {
        case .books(let page, _, _): paged("books", page)
        case .recent(let page, _): paged("recent", page)
        case .continueReading: components.path = "continue-reading"
        case .collections: components.path = "collections"
        case .collection(let id, let page, _, _): paged("collections/\(id)", page)
        case .smartScope(let id, let page, _, _): paged("smart-scopes/\(id)", page)
        case .seriesList(let page): paged("series", page)
        case .series(let id, let page, _, _): paged("series/\(id)", page)
        case .authors(let page): paged("authors", page)
        case .author(let id, let page, _, _): paged("authors/\(id)", page)
        case .search(let text, let page):
            query.append(URLQueryItem(name: "q", value: text))
            paged("search", page)
        }
        if let order {
            if let sort = order.sort, sort != sorts.first { query.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
            if order.filter != .all { query.append(URLQueryItem(name: "show", value: order.filter.rawValue)) }
        }
        if !query.isEmpty { components.queryItems = query }
        return LibraryLink(rawValue: components.string ?? "")
    }

    init?(_ link: LibraryLink) {
        guard let components = URLComponents(string: link.rawValue), components.scheme == nil, components.host == nil else { return nil }
        let items = components.queryItems ?? []
        let page = items.first { $0.name == "page" }?.value.flatMap(Int.init) ?? 0
        guard page >= 0 else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        let id = parts.count == 2 ? Int(parts[1]).flatMap { $0 > 0 ? $0 : nil } : nil
        var route: BookOrbitRoute
        switch (parts.first, parts.count, id) {
        case ("books", 1, _): route = .books(page: page)
        case ("recent", 1, _): route = .recent(page: page)
        case ("continue-reading", 1, _): route = .continueReading
        case ("collections", 1, _): route = .collections
        case ("collections", 2, let id?): route = .collection(id: id, page: page)
        case ("smart-scopes", 2, let id?): route = .smartScope(id: id, page: page)
        case ("series", 1, _): route = .seriesList(page: page)
        case ("series", 2, let id?): route = .series(id: id, page: page)
        case ("authors", 1, _): route = .authors(page: page)
        case ("authors", 2, let id?): route = .author(id: id, page: page)
        case ("search", 1, _):
            guard let query = items.first(where: { $0.name == "q" })?.value else { return nil }
            route = .search(query: query, page: page)
        default: return nil
        }
        if route.order != nil {
            let sort = items.first { $0.name == "sort" }?.value.flatMap(LibrarySort.init(rawValue:))
            let filter = items.first { $0.name == "show" }?.value.flatMap(LibraryFilter.init(rawValue:)) ?? .all
            route = route.ordered(sort, filter).paged(page)
        }
        self = route
    }

    /// The same list at `page`.
    private func paged(_ page: Int) -> BookOrbitRoute {
        switch self {
        case .books(_, let sort, let filter): .books(page: page, sort: sort, filter: filter)
        case .recent(_, let filter): .recent(page: page, filter: filter)
        case .collection(let id, _, let sort, let filter): .collection(id: id, page: page, sort: sort, filter: filter)
        case .smartScope(let id, _, let sort, let filter): .smartScope(id: id, page: page, sort: sort, filter: filter)
        case .series(let id, _, let sort, let filter): .series(id: id, page: page, sort: sort, filter: filter)
        case .author(let id, _, let sort, let filter): .author(id: id, page: page, sort: sort, filter: filter)
        case .seriesList: .seriesList(page: page)
        case .authors: .authors(page: page)
        case .search(let query, _): .search(query: query, page: page)
        case .continueReading, .collections: self
        }
    }
}

extension LibrarySort {
    /// The sort as BookOrbit's lists take it: `books/query` (title, author,
    /// recently added), `series/{id}/books` (reading order, title, recently
    /// added) and `authors/{id}/books` (title, recently added).
    var bookOrbit: BookOrbitBookSort {
        switch self {
        case .readingOrder: .readingOrder
        case .title: .title
        case .author: .author
        case .recentlyAdded: .newest
        }
    }
}

extension LibraryFilter {
    /// The `books/query` filter. `nil`: every book.
    var bookOrbit: BookOrbitBookFilter? {
        switch self {
        case .all: nil
        case .unread: .unread
        case .reading: .reading
        case .finished: .finished
        }
    }

    /// Whether `book` passes, as `bookOrbit` would on the server.
    func matches(_ book: BookOrbitBook) -> Bool {
        switch self {
        case .all: true
        case .unread: (book.readingFraction ?? 0) == 0 && (book.readStatus == nil || book.readStatus == "unread")
        case .reading: book.readStatus == "reading" || book.readStatus == "rereading"
        case .finished: book.readStatus == "read"
        }
    }
}
