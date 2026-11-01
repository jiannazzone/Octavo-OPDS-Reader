import Foundation

/// A BookOrbit server as a `LibrarySource`.
///
/// The chips are All, Collections (with smart scopes), Series and Authors.
/// Lists span every library the user can see; podcast collections and scopes
/// are left out. Search covers books, series and authors.
public struct BookOrbitSource: LibrarySource {
    public let client: BookOrbitClient
    /// Items per page, 1–100 (BookOrbit's limit for series and authors).
    public let pageSize: Int

    public init(client: BookOrbitClient, pageSize: Int = 50) {
        self.client = client
        self.pageSize = min(max(pageSize, 1), 100)
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
            continueReading: BookOrbitRoute.continueReading.link
        )
    }

    public func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        guard let route = BookOrbitRoute(link) else { throw LibraryError.invalidLink }
        return try await mappingErrors {
            switch route {
            case .books(let page):
                return bookFeed(try await client.books(sort: [.title], page: page, size: pageSize), title: "All", page: page) { .books(page: $0) }
            case .recent(let page):
                return bookFeed(try await client.books(sort: [.newest], page: page, size: pageSize), page: page) { .recent(page: $0) }
            case .continueReading:
                // One page: BookOrbit caps the list (its own home shows 20)
                // rather than paging it.
                let books = try await client.continueReading(limit: 20).map(Self.book)
                return LibraryFeed(title: "Continue reading", books: books, total: books.count)
            case .collections:
                async let collections = client.collections()
                async let scopes = client.smartScopes()
                let entries = try await collections.filter(\.holdsBooks).map(entry)
                    + (try await scopes).filter(\.holdsBooks).map(entry)
                return LibraryFeed(title: "Collections", entries: entries, total: entries.count)
            case .collection(let id, let page):
                return bookFeed(try await client.collectionBooks(collectionID: id, page: page, size: pageSize), page: page) { .collection(id: id, page: $0) }
            case .smartScope(let id, let page):
                return bookFeed(try await client.smartScopeBooks(scopeID: id, page: page, size: pageSize), page: page) { .smartScope(id: id, page: $0) }
            case .seriesList(let page):
                let series = try await client.series(page: page, size: pageSize)
                return LibraryFeed(title: "Series", entries: series.items.map(entry), total: series.total,
                                   next: next(after: page, of: series) { .seriesList(page: $0) })
            case .series(let id, let page):
                return bookFeed(try await client.seriesBooks(seriesID: id, page: page, size: pageSize), page: page) { .series(id: id, page: $0) }
            case .authors(let page):
                let authors = try await client.authors(page: page, size: pageSize)
                return LibraryFeed(title: "Authors", entries: authors.items.map(entry), total: authors.total,
                                   next: next(after: page, of: authors) { .authors(page: $0) })
            case .author(let id, let page):
                return bookFeed(try await client.authorBooks(authorID: id, page: page, size: pageSize), page: page) { .author(id: id, page: $0) }
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
                series: try await matches.series.map(entry),
                authors: try await matches.authors.map(entry)
            )
        }
    }

    public func details(for book: LibraryBook) async throws -> LibraryBookDetails {
        guard let id = Int(book.id.rawValue) else { throw LibraryError.invalidLink }
        let detail = try await mappingErrors { try await client.book(id: id) }
        var summary = Self.book(detail)
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

    private func bookFeed(
        _ page: BookOrbitPage<BookOrbitBook>, title: String? = nil, page number: Int,
        route: (Int) -> BookOrbitRoute
    ) -> LibraryFeed {
        LibraryFeed(title: title, books: page.items.map(Self.book), total: page.total, next: next(after: number, of: page, route))
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
            lastReadAt: book.readStatusUpdatedAt
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
            link: BookOrbitRoute.author(id: author.id, page: 0).link
        )
    }

    private static func cover(bookID: Int, version: String?) -> LibraryCover {
        LibraryCover(rawValue: "books/\(bookID)", version: version)
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
/// (`collections/1?page=2`).
enum BookOrbitRoute: Hashable, Sendable {
    case books(page: Int)
    case recent(page: Int)
    case continueReading
    case collections
    case collection(id: Int, page: Int)
    case smartScope(id: Int, page: Int)
    case seriesList(page: Int)
    case series(id: Int, page: Int)
    case authors(page: Int)
    case author(id: Int, page: Int)
    case search(query: String, page: Int)

    var link: LibraryLink {
        var components = URLComponents()
        var query: [URLQueryItem] = []
        func paged(_ path: String, _ page: Int) {
            components.path = path
            query.append(URLQueryItem(name: "page", value: String(page)))
        }
        switch self {
        case .books(let page): paged("books", page)
        case .recent(let page): paged("recent", page)
        case .continueReading: components.path = "continue-reading"
        case .collections: components.path = "collections"
        case .collection(let id, let page): paged("collections/\(id)", page)
        case .smartScope(let id, let page): paged("smart-scopes/\(id)", page)
        case .seriesList(let page): paged("series", page)
        case .series(let id, let page): paged("series/\(id)", page)
        case .authors(let page): paged("authors", page)
        case .author(let id, let page): paged("authors/\(id)", page)
        case .search(let text, let page):
            query.append(URLQueryItem(name: "q", value: text))
            paged("search", page)
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
        switch (parts.first, parts.count, id) {
        case ("books", 1, _): self = .books(page: page)
        case ("recent", 1, _): self = .recent(page: page)
        case ("continue-reading", 1, _): self = .continueReading
        case ("collections", 1, _): self = .collections
        case ("collections", 2, let id?): self = .collection(id: id, page: page)
        case ("smart-scopes", 2, let id?): self = .smartScope(id: id, page: page)
        case ("series", 1, _): self = .seriesList(page: page)
        case ("series", 2, let id?): self = .series(id: id, page: page)
        case ("authors", 1, _): self = .authors(page: page)
        case ("authors", 2, let id?): self = .author(id: id, page: page)
        case ("search", 1, _):
            guard let query = items.first(where: { $0.name == "q" })?.value else { return nil }
            self = .search(query: query, page: page)
        default: return nil
        }
    }
}
