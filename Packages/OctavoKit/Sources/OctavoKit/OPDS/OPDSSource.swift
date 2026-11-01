import Foundation

/// An OPDS 1.2 (Atom) or 2.0 (JSON) catalog as a `LibrarySource`.
///
/// Links, book and file IDs are the catalog's absolute URLs, so `feed`
/// follows whatever the server links. The chips are the root feed's own
/// entries, all of them, in the server's order (Adam, 2026-11-01). OPDS has
/// no reading progress, so `continueReading` is `nil`; the reader's
/// position stays on the iPhone.
public struct OPDSSource: LibrarySource {
    public let catalogURL: URL
    let client: OPDSClient
    private let state = State()

    /// - Parameters:
    ///   - catalogURL: the root feed, e.g. `…/opds` (Calibre-Web),
    ///     `…/feed` (COPS), `…/opds/v1.2/catalog` (Komga) or the link from
    ///     Kavita's settings.
    ///   - transport: #9's `ServerTransport` for this server; a plain
    ///     `URLSession` in tests.
    ///   - credentials: the HTTP Basic sign-in, if the catalog asked for one.
    public init(
        catalogURL: URL,
        transport: any HTTPTransport = URLSession(configuration: .ephemeral),
        credentials: any PasswordStore = InMemoryPasswordStore()
    ) {
        self.catalogURL = catalogURL
        client = OPDSClient(catalogURL: catalogURL, transport: transport, credentials: credentials)
    }

    /// Whether the catalog needs a sign-in, trying the stored one if any.
    /// For the add-server form (#12): show the account fields only for
    /// `.signInRequired`.
    public func checkAccess() async throws -> OPDSAccess {
        try await client.checkAccess()
    }

    // MARK: - LibrarySource

    public func root() async throws -> LibraryRoot {
        let feed = try await client.feed(at: catalogURL)
        await state.setRoot(feed)
        let mapped = mapFeed(feed, at: catalogURL)
        await state.remember(mapped.publications)
        var chips = mapped.feed.entries
        // A root that lists books itself gets a chip of its own (one with
        // nothing else gets only that).
        if !mapped.feed.books.isEmpty || chips.isEmpty {
            chips.append(LibraryEntry(kind: .feed, title: feed.title ?? "All books", link: Self.link(catalogURL)))
        }
        let hints = OPDSCatalogHints(feed: feed)
        return LibraryRoot(
            title: feed.title,
            chips: chips,
            search: Self.searchLink(in: feed) != nil ? .books : .unavailable,
            recentlyAdded: hints.recentlyAdded.map(Self.link),
            startChip: hints.startChip(among: chips)
        )
    }

    public func feed(_ link: LibraryLink) async throws -> LibraryFeed {
        let url = try Self.url(link)
        let feed = try await client.feed(at: url)
        let mapped = mapFeed(feed, at: url)
        await state.remember(mapped.publications)
        return mapped.feed
    }

    public func search(_ query: String) async throws -> LibrarySearchResults {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let url = try await searchTemplate()?.url(for: query) else {
            return LibrarySearchResults(query: query)
        }
        return LibrarySearchResults(query: query, books: try await feed(Self.link(url)))
    }

    public func details(for book: LibraryBook) async throws -> LibraryBookDetails {
        guard var publication = await state.publication(book.id) else {
            // Not from a list this source loaded (a book remembered from an
            // earlier launch): only what the list gave.
            return LibraryBookDetails(book: book)
        }
        if let full = Self.fullEntryLink(of: publication),
           let fetched = try? await client.feed(at: full).publications.first {
            publication = fetched
            await state.remember([(book.id, fetched)])
        }
        var summary = mapBook(publication)
        summary.id = book.id
        summary.progress = book.progress
        let template = try? await searchTemplate()
        let authors = publication.authors.compactMap { author -> LibraryEntry? in
            guard let link = authorLink(author) ?? template?.url(for: author.name) else { return nil }
            return LibraryEntry(kind: .author, title: author.name, sortName: author.sortAs, link: Self.link(link))
        }
        return LibraryBookDetails(
            book: summary,
            subtitle: publication.subtitle,
            description: publication.summary,
            publisher: publication.publisher,
            language: publication.language,
            published: publication.published.map(Self.date),
            authors: authors,
            series: summary.series.map { [$0] } ?? []
        )
    }

    public func cover(_ cover: LibraryCover, size: LibraryCoverSize) async throws -> Data {
        guard let images = CoverImages(cover) else { throw LibraryError.invalidLink }
        let url = size == .thumbnail ? images.thumbnail ?? images.full : images.full ?? images.thumbnail
        guard let url, let resolved = URL(string: url) else { throw LibraryError.invalidLink }
        return try await client.data(at: resolved, accept: "image/*").0
    }

    @discardableResult
    public func download(_ file: LibraryFile, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let url = URL(string: file.id.rawValue) else { throw LibraryError.invalidLink }
        return try await client.download(url, to: destination, progress: progress)
    }

    // MARK: - Links

    static func link(_ url: URL) -> LibraryLink {
        LibraryLink(rawValue: url.absoluteString)
    }

    /// Only absolute http(s) URLs: anything else wasn't made here.
    static func url(_ link: LibraryLink) throws -> URL {
        guard let url = URL(string: link.rawValue), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else {
            throw LibraryError.invalidLink
        }
        return url
    }

    private static func searchLink(in feed: OPDSFeed) -> OPDSLink? {
        feed.links.first { $0.has(rel: "search") }
    }

    /// Prefers a template linked straight from the root (Calibre-Web, OPDS
    /// 2) to fetching the OpenSearch description. Kept once found.
    private func searchTemplate() async throws -> OPDSSearchTemplate? {
        if let cached = await state.searchTemplate { return cached }
        let root: OPDSFeed
        if let cached = await state.root {
            root = cached
        } else {
            root = try await client.feed(at: catalogURL)
            await state.setRoot(root)
        }
        let links = root.links.filter { $0.has(rel: "search") }
        var template: OPDSSearchTemplate?
        if let direct = links.first(where: { $0.isTemplate && $0.mediaType != "application/opensearchdescription+xml" }) {
            template = OPDSSearchTemplate(template: direct.href, base: direct.base)
        } else if let description = links.first(where: { !$0.isTemplate })?.url {
            let (data, response) = try await client.data(at: description, accept: "application/opensearchdescription+xml, application/xml;q=0.9, */*;q=0.5")
            template = OpenSearchDescriptionParser.template(in: data, url: response.url ?? description)
        }
        await state.setSearchTemplate(template)
        return template
    }

    /// The complete entry, when a list sends a partial one.
    private static func fullEntryLink(of publication: OPDSPublication) -> URL? {
        publication.links.first { link in
            let type = link.type?.lowercased() ?? ""
            return (link.has(rel: "alternate") && type.contains("type=entry"))
                || (link.has(rel: "self") && type.contains("opds-publication+json"))
        }?.url
    }

    /// An author's books, if the server links them from the catalog itself.
    /// Atom `<uri>` is often a web page or a made-up URI (Kavita), so it
    /// counts only on the catalog's own origin.
    private func authorLink(_ author: OPDSContributor) -> URL? {
        guard let link = author.link, let url = link.url else { return nil }
        if link.type != nil { return link.isCatalog ? url : nil }
        return OPDSClient.origin(of: url) == OPDSClient.origin(of: catalogURL) ? url : nil
    }

    /// `2008-06-27T08:08:08Z` → `2008-06-27`; anything else as sent.
    static func date(_ value: String) -> String {
        let parts = value.split(separator: "T", maxSplits: 1)
        if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isNumber || $0 == "-" }) {
            return String(parts[0])
        }
        return value
    }

    // MARK: - Mapping

    struct MappedFeed {
        var feed: LibraryFeed
        var publications: [(LibraryBookID, OPDSPublication)]
    }

    func mapFeed(_ feed: OPDSFeed, at url: URL) -> MappedFeed {
        let here = Set([url, feed.link(rel: "self")?.url].compactMap { $0.map(Self.normalized) })
        var entries: [LibraryEntry] = []
        var publications = feed.publications
        func add(_ navigation: [OPDSNavigation]) {
            for item in navigation {
                guard let target = item.link.url, !here.contains(Self.normalized(target)), let entry = mapEntry(item) else { continue }
                entries.append(entry)
            }
        }
        add(feed.navigation)
        for group in feed.groups {
            // A group is a preview of its own list: one entry that opens it.
            if let list = group.links.first(where: { $0.has(rel: "self") })?.url, !here.contains(Self.normalized(list)) {
                entries.append(LibraryEntry(
                    kind: .feed,
                    title: group.title,
                    count: group.numberOfItems,
                    previewCovers: group.publications.prefix(3).compactMap(Self.cover),
                    link: Self.link(list)
                ))
            } else {
                add(group.navigation)
                publications += group.publications
            }
        }
        let books = publications.map(mapBook)
        let next = feed.link(rel: "next")?.url.map(Self.link)
        return MappedFeed(
            feed: LibraryFeed(
                title: feed.title,
                entries: entries,
                books: books,
                total: feed.totalResults ?? (next == nil ? entries.count + books.count : nil),
                next: next
            ),
            publications: zip(books.map(\.id), publications).map { ($0, $1) }
        )
    }

    func mapEntry(_ item: OPDSNavigation) -> LibraryEntry? {
        guard let url = item.link.url else { return nil }
        let summary = item.summary.map { PlainText.containsMarkup($0) ? PlainText.fromHTML($0) : $0 }
        let authors = item.authors.map(\.name).joined(separator: ", ")
        return LibraryEntry(
            kind: .feed,
            title: item.title,
            subtitle: authors.isEmpty ? summary?.nilIfEmpty : authors,
            count: item.link.count,
            // Only real cover art: COPS gives its list entries an icon as
            // a thumbnail, which isn't a book's cover.
            previewCovers: item.images.contains { $0.has(rel: OPDSRel.image) || $0.has(rel: OPDSRel.stanzaImage) }
                ? Self.cover(images: item.images).map { [$0] } ?? [] : [],
            link: Self.link(url)
        )
    }

    func mapBook(_ publication: OPDSPublication) -> LibraryBook {
        let files = Self.files(of: publication)
        let id = publication.identifier
            ?? publication.links.first { $0.has(rel: "self") || $0.has(rel: "alternate") }?.url?.absoluteString
            ?? files.first?.id.rawValue
            ?? publication.title
        let series = publication.series.first.map { series in
            LibrarySeriesPosition(
                name: series.name,
                position: series.position,
                link: series.link.flatMap { $0.isCatalog || $0.type == nil ? $0.url : nil }.map(Self.link)
            )
        }
        return LibraryBook(
            id: LibraryBookID(rawValue: id),
            title: Self.title(publication.title),
            authors: publication.authors.map(\.name),
            series: series,
            cover: Self.cover(publication),
            files: files
        )
    }

    /// Kavita marks read state with a glyph before the title ("⭘ ", "◔ ",
    /// "⬤ ") and repeats a one-book series' name ("Alice - Alice").
    static func title(_ title: String) -> String {
        var title = title.trimmingCharacters(in: .whitespaces)
        if let first = title.unicodeScalars.first, ["\u{2B58}", "\u{25D4}", "\u{25D1}", "\u{25D5}", "\u{2B24}", "\u{25CB}", "\u{25CF}"].contains(first),
           title.dropFirst().first == " " {
            title = String(title.dropFirst(2))
        }
        let halves = title.components(separatedBy: " - ")
        if halves.count == 2, halves[0] == halves[1] { title = halves[0] }
        return title
    }

    /// Direct downloads only, most wanted format first and marked primary.
    /// Purchases, loans, samples and anything behind a DRM licence or a web
    /// page (indirect acquisition) are left out.
    static func files(of publication: OPDSPublication) -> [LibraryFile] {
        var seen = Set<String>()
        let links = publication.acquisitions.filter { link in
            guard link.rels.contains(where: { $0 == OPDSRel.acquisition || $0 == OPDSRel.openAccess }),
                  link.indirectTypes.isEmpty, let url = link.url else { return false }
            return seen.insert(url.absoluteString).inserted
        }
        return OPDSFormats.sorted(links, format: OPDSFormats.format(of:)).enumerated().map { index, link in
            let url = link.url!
            let name = url.lastPathComponent
            return LibraryFile(
                id: LibraryFileID(rawValue: url.absoluteString),
                format: OPDSFormats.format(of: link),
                sizeBytes: link.length,
                filename: name.contains(".") ? name : nil,
                isPrimary: index == 0
            )
        }
    }

    static func cover(_ publication: OPDSPublication) -> LibraryCover? {
        cover(images: publication.images + publication.links)
    }

    /// Both sizes in one opaque value: the full image and the thumbnail.
    static func cover(images links: [OPDSLink]) -> LibraryCover? {
        func first(_ rels: String...) -> OPDSLink? {
            links.first { link in rels.contains { link.has(rel: $0) } && link.url != nil }
        }
        var full = first(OPDSRel.image, OPDSRel.stanzaImage)?.url
        var thumbnail = first(OPDSRel.thumbnail, OPDSRel.stanzaThumbnail)?.url
        // OPDS 2 `images`: no rels, sizes instead.
        let sized = links.filter { $0.rels.isEmpty && ($0.mediaType?.hasPrefix("image/") ?? true) && $0.url != nil }
            .sorted { ($0.width ?? 0) * ($0.height ?? 0) < ($1.width ?? 0) * ($1.height ?? 0) }
        if full == nil { full = sized.last?.url }
        if thumbnail == nil { thumbnail = sized.first?.url }
        guard full != nil || thumbnail != nil else { return nil }
        return CoverImages(full: full?.absoluteString, thumbnail: thumbnail?.absoluteString).cover
    }

    private static func normalized(_ url: URL) -> String {
        var string = url.absoluteString
        while string.hasSuffix("?") || string.hasSuffix("/") { string.removeLast() }
        return string
    }
}

/// `LibraryCover.rawValue`: JSON with the full image and the thumbnail.
struct CoverImages: Codable, Hashable {
    var full: String?
    var thumbnail: String?

    init(full: String?, thumbnail: String?) {
        self.full = full
        self.thumbnail = thumbnail
    }

    init?(_ cover: LibraryCover) {
        guard let value = try? JSONDecoder().decode(Self.self, from: Data(cover.rawValue.utf8)) else { return nil }
        self = value
    }

    var cover: LibraryCover {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return LibraryCover(rawValue: String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self))
    }
}

/// What the source keeps between calls: the root feed, the search template,
/// and the books it has listed (OPDS has no detail request to fall back on).
private actor State {
    private(set) var root: OPDSFeed?
    /// `.some(nil)`: looked, and the catalog has no search.
    private(set) var searchTemplate: OPDSSearchTemplate??
    private var publications: [LibraryBookID: OPDSPublication] = [:]

    func setRoot(_ feed: OPDSFeed) {
        root = feed
    }

    func setSearchTemplate(_ template: OPDSSearchTemplate?) {
        searchTemplate = .some(template)
    }

    func remember(_ items: [(LibraryBookID, OPDSPublication)]) {
        // A rough bound; lists reload what they need.
        if publications.count > 5_000 { publications.removeAll() }
        for (id, publication) in items { publications[id] = publication }
    }

    func publication(_ id: LibraryBookID) -> OPDSPublication? {
        publications[id]
    }
}
