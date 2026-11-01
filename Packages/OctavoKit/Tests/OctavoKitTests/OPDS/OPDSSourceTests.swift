import Foundation
@testable import OctavoKit
import Synchronization
import Testing

private extension StubServer.Response {
    static func atom(_ body: String, status: Int = 200) -> Self {
        Self(status: status, headers: ["Content-Type": "application/atom+xml;profile=opds-catalog"], body: Data(body.utf8))
    }

    static func opds2(_ body: String) -> Self {
        Self(status: 200, headers: ["Content-Type": "application/opds+json"], body: Data(body.utf8))
    }

    static func xml(_ body: String) -> Self {
        Self(status: 200, headers: ["Content-Type": "application/opensearchdescription+xml"], body: Data(body.utf8))
    }

    static func bytes(_ body: String, type: String = "application/octet-stream") -> Self {
        Self(status: 200, headers: ["Content-Type": type], body: Data(body.utf8))
    }

    static let notFound = Self(status: 404, headers: [:], body: Data())
}

private func source(
    _ server: StubServer, path: String = "/catalog", credentials: (any PasswordStore)? = nil,
    scheme: HTTPAuthScheme? = .basic, secret: OPDSURLSecret? = nil
) -> OPDSSource {
    OPDSSource(
        catalogURL: server.baseURL.appending(path: path),
        transport: ServerTransport(server: server.baseURL, configuration: server.configuration),
        credentials: credentials ?? InMemoryPasswordStore(),
        authScheme: scheme,
        secret: secret
    )
}

/// Fails every request the way an offline phone does, with the URL attached.
private struct FailingTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: request.url as Any, NSURLErrorFailingURLStringErrorKey: request.url?.absoluteString as Any])
    }

    func download(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (URL, URLResponse) {
        throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: request.url as Any])
    }
}

/// Counts reads, to check the source doesn't read the Keychain per request.
private actor CountingPasswordStore: PasswordStore {
    var credentials: PasswordCredentials?
    private(set) var loads = 0

    init(_ credentials: PasswordCredentials?) {
        self.credentials = credentials
    }

    func load() -> PasswordCredentials? {
        loads += 1
        return credentials
    }

    func save(_ credentials: PasswordCredentials?) {
        self.credentials = credentials
    }
}

/// Serves `routes` by path; anything else is a 404.
private func server(_ routes: [String: StubServer.Response]) -> StubServer {
    StubServer { routes[$0.path] ?? .notFound }
}

private func url(_ server: StubServer, _ path: String) -> String {
    server.baseURL.absoluteString + path
}

struct OPDSParserTests {
    private let base = URL(string: "https://catalog.test/catalog")!

    @Test func readsAtomNavigationEntries() throws {
        let feed = try OPDSAtomParser.parse(Data(OPDSFixtures.atomRoot.utf8), url: base)
        #expect(feed.title == "Harbour Library")
        #expect(feed.navigation.map(\.title) == ["Shelf picks", "Everything", "Writers"])
        #expect(feed.navigation[1].link.count == 42)
        #expect(feed.navigation[2].summary == "<div>By <b>name</b></div>")
        #expect(feed.navigation[2].link.url?.absoluteString == "https://catalog.test/catalog/writers")
        #expect(feed.publications.isEmpty)
        #expect(feed.link(rel: "search")?.mediaType == "application/opensearchdescription+xml")
    }

    @Test func readsAtomBooks() throws {
        let feed = try OPDSAtomParser.parse(Data(OPDSFixtures.atomBooks.utf8), url: base)
        #expect(feed.totalResults == 3)
        #expect(feed.link(rel: "next")?.url?.absoluteString == "https://catalog.test/catalog/all?page=2")
        let almanac = try #require(feed.publications.first)
        #expect(almanac.title == "The Lighthouse Keeper's Almanac")
        #expect(almanac.authors.map(\.name) == ["Mara Quill", "Tobias Fenn"])
        #expect(almanac.language == "en")
        #expect(almanac.publisher == "Tidewater Press")
        #expect(almanac.published == "1911-04-02T08:00:00Z")
        #expect(almanac.summary == "<div><p>A year of <i>weather</i> &amp; lamps.</p></div>")
        let loan = try #require(almanac.links.first { $0.href == "/loan/1" })
        #expect(loan.indirectTypes == ["application/epub+zip"])
        #expect(feed.publications[1].summary == "Short summary only.")
    }

    @Test func readsASingleAtomEntry() throws {
        let feed = try OPDSAtomParser.parse(Data(OPDSFixtures.atomEntry.utf8), url: base)
        #expect(feed.publications.map(\.title) == ["Salt Roads"])
        #expect(feed.publications.first?.summary == "<p>The long version.</p>")
    }

    @Test func readsOPDS2() throws {
        let feed = try OPDSJSONParser.parse(Data(OPDSFixtures.json.utf8), url: base)
        #expect(feed.title == "Harbour Library")
        #expect(feed.totalResults == 7)
        #expect(feed.navigation.map(\.title) == ["Home", "Browse"])
        #expect(feed.navigation[1].link.count == 12)
        #expect(feed.groups.map(\.title) == ["Latest Books", "Shelves"])
        // The publication with no metadata is dropped, not fatal.
        #expect(feed.publications.map(\.title) == ["Fog Signals"])
        #expect(feed.publications[0].authors.map(\.name) == ["Ines Calder"])
        let tide = try #require(feed.groups.first?.publications.first)
        #expect(tide.title == "Tide Tables")
        #expect(tide.authors.first?.sortAs == "Quill, Mara")
        #expect(tide.series == [OPDSSeries(name: "Coastal Almanacs", position: 2, link: OPDSLink(href: "/v2/series/3", base: base, type: "application/opds+json"))])
        #expect(feed.link(rel: "search")?.templated == true)
    }

    @Test(arguments: ["<html><body>Sign in</body></html>", "not a feed", "{\"error\":\"nope\"}", ""])
    func rejectsWhatIsNotACatalog(body: String) {
        #expect(throws: LibraryError.invalidResponse) {
            let response = HTTPURLResponse(url: base, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": body.hasPrefix("<html") ? "text/html" : "text/plain"])!
            _ = try OPDSClient.parseFeed(Data(body.utf8), response: response, requested: base)
        }
    }
}

struct OPDSFormatTests {
    private let base = URL(string: "https://catalog.test/")!

    private func format(_ href: String, _ type: String?, title: String? = nil) -> String? {
        OPDSFormats.format(of: OPDSLink(href: href, base: base, rels: [OPDSRel.acquisition], type: type, title: title))
    }

    @Test func mapsTypesFromTheFormatsSpike() {
        #expect(format("/a", "application/epub+zip") == "epub")
        #expect(format("/a", "application/x-mobipocket-ebook") == "mobi")
        #expect(format("/a", "application/x-mobi8-ebook") == "azw3")
        #expect(format("/a", "application/vnd.amazon.ebook") == "azw3")
        #expect(format("/a", "application/x-fictionbook+xml") == "fb2")
        #expect(format("/a", "text/fb2+xml") == "fb2")
        #expect(format("/a", "application/x-zip-compressed-fb2") == "fbz")
        #expect(format("/a", "application/pdf; charset=binary") == "pdf")
        #expect(format("/a", "application/x-unknown") == nil)
    }

    @Test func trustsTheTitleOrExtensionOverTheType() {
        // Calibre-Web: AZW3 and MOBI share a type; plain FB2 is sent as fb2+zip.
        #expect(format("/download/6/azw3/", "application/x-mobipocket-ebook", title: "AZW3") == "azw3")
        #expect(format("/download/6/mobi/", "application/x-mobipocket-ebook", title: "MOBI") == "mobi")
        #expect(format("/download/6/fb2/", "application/fb2+zip", title: "FB2") == "fb2")
        #expect(format("/get/book.fb2.zip", "application/octet-stream") == "fbz")
        #expect(format("/get/book.azw3", nil) == "azw3")
        #expect(format("/get/book.kepub.epub", "application/kepub+zip") == "epub")
    }

    @Test func ordersEPUBFirstThenKindleThenFB2() {
        let order = OPDSFormats.sorted(["pdf", "mobi", "fb2", "cbz", "azw3", "epub", "fbz"]) { $0 }
        #expect(order == ["epub", "azw3", "mobi", "fb2", "fbz", "pdf", "cbz"])
    }
}

struct OPDSSearchTemplateTests {
    private let base = URL(string: "https://catalog.test/catalog/")!

    @Test func fillsOpenSearchTemplates() {
        let template = OPDSSearchTemplate(template: "/catalog/search?q={searchTerms}&page={startPage?}", base: base)
        #expect(template.url(for: "salt & pepper")?.absoluteString == "https://catalog.test/catalog/search?q=salt%20%26%20pepper&page=")
        let path = OPDSSearchTemplate(template: "/opds/search/{searchTerms}", base: base)
        #expect(path.url(for: "a b/c?")?.absoluteString == "https://catalog.test/opds/search/a%20b%2Fc%3F")
        let prefixed = OPDSSearchTemplate(template: "search?q={opensearch:searchTerms}", base: base)
        #expect(prefixed.url(for: "Brontë")?.absoluteString == "https://catalog.test/catalog/search?q=Bront%C3%AB")
    }

    @Test func fillsRFC6570Templates() {
        let template = OPDSSearchTemplate(template: "/v2/search{?query,author}", base: base)
        #expect(template.url(for: "tide")?.absoluteString == "https://catalog.test/v2/search?query=tide")
        let simple = OPDSSearchTemplate(template: "/v2/search/{query}", base: base)
        #expect(simple.url(for: "tide")?.absoluteString == "https://catalog.test/v2/search/tide")
    }

    @Test func picksTheFeedURLFromAnOpenSearchDescription() throws {
        let template = try OpenSearchDescriptionParser.template(in: Data(OPDSFixtures.openSearchDescription.utf8), url: base)
        #expect(template?.template == "/catalog/search?q={searchTerms}&page={startPage?}")
        #expect(throws: LibraryError.invalidResponse) { try OpenSearchDescriptionParser.template(in: Data("<html/>".utf8), url: base) }
    }
}

struct OPDSSourceTests {
    @Test func rootEntriesBecomeChips() async throws {
        let server = server(["/catalog": .atom(OPDSFixtures.atomRoot)])
        let root = try await source(server).root()
        #expect(root.title == "Harbour Library")
        #expect(root.chips.map(\.title) == ["Shelf picks", "Everything", "Writers"])
        #expect(root.chips.map(\.link.rawValue) == [url(server, "/catalog/picks"), url(server, "/catalog/all"), url(server, "/catalog/writers")])
        #expect(root.chips[0].subtitle == "Hand-picked by the harbour master")
        #expect(root.chips[1].count == 42)
        // COPS's icons aren't covers.
        #expect(root.chips[1].previewCovers.isEmpty)
        #expect(root.chips[2].subtitle == "By name")
        #expect(root.search == .books)
        #expect(root.recentlyAdded?.rawValue == url(server, "/catalog/newest"))
        #expect(root.startChip?.rawValue == url(server, "/catalog/all"))
        #expect(root.continueReading == nil)
    }

    @Test func aRootWithOnlyBooksIsOneChip() async throws {
        let server = server(["/catalog": .atom(OPDSFixtures.atomBooksOnlyRoot)])
        let root = try await source(server).root()
        #expect(root.chips.map(\.title) == ["Pocket Shelf"])
        #expect(root.chips.first?.link.rawValue == url(server, "/catalog"))
        #expect(root.search == .unavailable)
        #expect(root.recentlyAdded == nil)
        let feed = try await source(server).feed(root.chips[0].link)
        #expect(feed.books.map(\.title) == ["Salt Roads"])
    }

    @Test func guessesRecentlyAddedAndTheStartChip() async throws {
        let calibreWeb = server(["/opds": .atom(OPDSFixtures.atomRootCalibreWebStyle)])
        let root = try await source(calibreWeb, path: "/opds").root()
        #expect(root.recentlyAdded?.rawValue == url(calibreWeb, "/opds/new"))
        #expect(root.startChip?.rawValue == url(calibreWeb, "/opds/books"))

        let kavita = server(["/api/opds/KEY": .atom(OPDSFixtures.atomRootKavitaStyle)])
        let kavitaRoot = try await source(kavita, path: "/api/opds/KEY").root()
        #expect(kavitaRoot.recentlyAdded?.rawValue == url(kavita, "/api/opds/KEY/recently-added"))
        #expect(kavitaRoot.startChip?.rawValue == url(kavita, "/api/opds/KEY/libraries"))
        #expect(kavitaRoot.search == .unavailable)
    }

    @Test func booksListTheirFilesMostWantedFirst() async throws {
        let server = server(["/catalog/all": .atom(OPDSFixtures.atomBooks)])
        let feed = try await source(server).feed(LibraryLink(rawValue: url(server, "/catalog/all")))
        #expect(feed.title == "Everything")
        #expect(feed.total == 3)
        #expect(feed.next?.rawValue == url(server, "/catalog/all?page=2"))
        #expect(feed.entries.isEmpty)

        let almanac = try #require(feed.books.first)
        #expect(almanac.id.rawValue == "urn:uuid:11111111-1111-4111-8111-111111111111")
        #expect(almanac.authors == ["Mara Quill", "Tobias Fenn"])
        // The purchase and the DRM loan are left out.
        #expect(almanac.files.map(\.format) == ["epub", "azw3", "mobi", "pdf"])
        #expect(almanac.files.map(\.isPrimary) == [true, false, false, false])
        #expect(almanac.files.map(\.sizeBytes) == [200, 310, 300, 900])
        #expect(almanac.files.first?.id.rawValue == url(server, "/get/1.epub"))
        #expect(almanac.files.first?.filename == "1.epub")
        #expect(almanac.files[1].filename == nil)
        #expect(almanac.primaryFile?.format == "epub")

        let saltRoads = feed.books[1]
        #expect(saltRoads.files.map(\.format) == ["azw3", "fb2", "fbz"])
        #expect(saltRoads.cover == nil)
    }

    @Test func groupsWithTheirOwnListBecomeEntries() async throws {
        let server = server(["/v2/home": .opds2(OPDSFixtures.json)])
        let feed = try await source(server, path: "/v2/home").feed(LibraryLink(rawValue: url(server, "/v2/home")))
        // "Home" is this feed; "Shelves" has no list of its own, so its
        // entries are listed here.
        #expect(feed.entries.map(\.title) == ["Browse", "Latest Books", "Winter reads"])
        #expect(feed.entries.map(\.count) == [12, 2, nil])
        #expect(feed.entries[1].previewCovers.count == 1)
        #expect(feed.books.map(\.title) == ["Fog Signals"])
        #expect(feed.books.first?.files.map(\.format) == ["fb2"])
        #expect(feed.total == 7)
        #expect(feed.next?.rawValue == url(server, "/v2/home?page=2"))
    }

    @Test func coversPickTheSizeAsked() async throws {
        let server = server([
            "/v2/latest": .opds2(#"{"metadata":{"title":"Latest"},"publications":[\#(OPDSFixtures.tideTables)]}"#),
            "/v2/books/a/small.jpg": .bytes("small", type: "image/jpeg"),
            "/v2/books/a/large.jpg": .bytes("large", type: "image/jpeg"),
        ])
        let source = source(server, path: "/v2/home")
        let book = try #require(try await source.feed(LibraryLink(rawValue: url(server, "/v2/latest"))).books.first)
        #expect(book.series == LibrarySeriesPosition(name: "Coastal Almanacs", position: 2, link: LibraryLink(rawValue: url(server, "/v2/series/3"))))
        let cover = try #require(book.cover)
        #expect(try await source.cover(cover, size: .thumbnail) == Data("small".utf8))
        #expect(try await source.cover(cover, size: .full) == Data("large".utf8))
        await #expect(throws: LibraryError.invalidLink) { try await source.cover(LibraryCover(rawValue: "42"), size: .full) }
    }

    @Test func detailsComeFromTheListedEntry() async throws {
        let server = server([
            "/catalog": .atom(OPDSFixtures.atomRoot),
            "/catalog/opensearch.xml": .xml(OPDSFixtures.openSearchDescription),
            "/catalog/all": .atom(OPDSFixtures.atomBooks),
        ])
        let source = source(server)
        let almanac = try #require(try await source.feed(LibraryLink(rawValue: url(server, "/catalog/all"))).books.first)
        let details = try await source.details(for: almanac)
        #expect(details.book.title == almanac.title)
        #expect(details.description.map(PlainText.fromHTML) == "A year of weather & lamps.")
        #expect(details.publisher == "Tidewater Press")
        #expect(details.language == "en")
        #expect(details.published == "1911-04-02")
        // Mara's link is on the catalog; Tobias's is a web page elsewhere, so
        // he gets a search for his name.
        #expect(details.authors.map(\.title) == ["Mara Quill", "Tobias Fenn"])
        #expect(details.authors.map(\.link.rawValue) == [url(server, "/catalog/authors/7"), url(server, "/catalog/search?q=Tobias%20Fenn&page=")])

        let stranger = LibraryBook(id: LibraryBookID(rawValue: "urn:unknown"), title: "Unknown")
        #expect(try await source.details(for: stranger) == LibraryBookDetails(book: stranger))
    }

    @Test func detailsFollowTheFullEntryLink() async throws {
        let list = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Short</title><entry>
          <title>Salt Roads</title><id>urn:uuid:22222222-2222-4222-8222-222222222222</id>
          <link rel="alternate" href="/catalog/entry/2" type="application/atom+xml;type=entry;profile=opds-catalog"/>
          <link rel="http://opds-spec.org/acquisition" href="/get/2.epub" type="application/epub+zip"/>
        </entry></feed>
        """
        let server = server(["/catalog/short": .atom(list), "/catalog/entry/2": .atom(OPDSFixtures.atomEntry), "/catalog": .atom(OPDSFixtures.atomBooksOnlyRoot)])
        let source = source(server)
        let book = try #require(try await source.feed(LibraryLink(rawValue: url(server, "/catalog/short"))).books.first)
        let details = try await source.details(for: book)
        #expect(details.description == "<p>The long version.</p>")
        #expect(details.book.id == book.id)
    }

    @Test func searchesThroughTheOpenSearchDescription() async throws {
        let results = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Results</title><entry><title>Salt Roads</title><id>2</id>
        <link rel="http://opds-spec.org/acquisition" href="/get/2.epub" type="application/epub+zip"/></entry></feed>
        """
        let server = server([
            "/catalog": .atom(OPDSFixtures.atomRoot),
            "/catalog/opensearch.xml": .xml(OPDSFixtures.openSearchDescription),
            "/catalog/search": .atom(results),
        ])
        let source = source(server)
        let found = try await source.search("  salt & pepper ")
        #expect(found.query == "salt & pepper")
        #expect(found.books.books.map(\.title) == ["Salt Roads"])
        #expect(server.requests(to: "/catalog/search").first?.query["q"] == "salt & pepper")
        _ = try await source.search("again")
        #expect(server.requests(to: "/catalog/opensearch.xml").count == 1, "the template is kept")
        #expect(try await source.search("   ").books.books.isEmpty)
    }

    @Test func searchesWithATemplateInTheRoot() async throws {
        let server = server([
            "/opds": .atom(OPDSFixtures.atomRootCalibreWebStyle),
            "/opds/search/salt roads": .atom(OPDSFixtures.atomBooksOnlyRoot),
        ])
        let found = try await source(server, path: "/opds").search("salt roads")
        #expect(found.books.books.map(\.title) == ["Salt Roads"])
        #expect(server.requests(to: "/opds/osd").isEmpty)
    }

    @Test func withoutSearchResultsAreEmpty() async throws {
        let server = server(["/catalog": .atom(OPDSFixtures.atomBooksOnlyRoot)])
        let results = try await source(server).search("salt")
        #expect(results == LibrarySearchResults(query: "salt"))
        #expect(server.requests.map(\.path) == ["/catalog"])
    }

    @Test func signsInOnlyOnTheCatalogsOrigin() async throws {
        let credentials = PasswordCredentials(username: "keeper", password: "lamp-oil")
        let expected = "Basic " + Data("keeper:lamp-oil".utf8).base64EncodedString()
        let images = StubServer { _ in .bytes("jpeg", type: "image/jpeg") }
        let catalog = StubServer { request in
            guard request.headers["authorization"] == expected else { return .atom("", status: 401) }
            switch request.path {
            case "/catalog/all":
                let feed = OPDSFixtures.atomBooks.replacingOccurrences(of: "href=\"/covers/", with: "href=\"\(images.baseURL.absoluteString)/covers/")
                return .atom(feed)
            case "/get/1.epub": return .bytes("PK-epub")
            default: return .notFound
            }
        }
        let source = source(catalog, credentials: InMemoryPasswordStore(credentials))
        let book = try #require(try await source.feed(LibraryLink(rawValue: url(catalog, "/catalog/all"))).books.first)
        _ = try await source.cover(try #require(book.cover), size: .full)
        #expect(images.requests.count == 1)
        #expect(images.requests.allSatisfy { $0.headers["authorization"] == nil }, "never sent to another host")

        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-opds-\(UUID().uuidString)/book.epub")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        try await source.download(try #require(book.primaryFile), to: destination)
        #expect(try Data(contentsOf: destination) == Data("PK-epub".utf8))
    }

    @Test func aRefusedSignInIsSignedOut() async throws {
        let server = StubServer { _ in .atom("", status: 401) }
        await #expect(throws: LibraryError.signedOut) { try await source(server).root() }
        await #expect(throws: LibraryError.notFound) { try await source(StubServer { _ in .notFound }).root() }
    }

    @Test func checksWhetherASignInIsNeeded() async throws {
        let open = server(["/catalog": .atom(OPDSFixtures.atomRoot)])
        #expect(try await source(open).checkAccess() == .open(title: "Harbour Library"))

        // Komga: the Authentication Document comes with the 401.
        let komga = StubServer { _ in
            StubServer.Response(status: 401, headers: ["Content-Type": "application/opds-authentication+json", "WWW-Authenticate": "Basic realm=\"Realm\""], body: Data(OPDSFixtures.authenticationDocument.utf8))
        }
        #expect(try await source(komga).checkAccess() == .signInRequired(OPDSSignInRequest(
            title: "Harbour", description: "Use your harbour pass.", usernameLabel: "Email", passwordLabel: "Passphrase"
        )))

        // Linked from the 401 instead.
        let linked = StubServer { request in
            if request.path == "/auth" { return .opds2(OPDSFixtures.oauthOnlyDocument) }
            return StubServer.Response(status: 401, headers: ["Link": "</auth>; rel=\"http://opds-spec.org/auth/document\"; type=\"application/opds-authentication+json\""], body: Data())
        }
        #expect(try await source(linked).checkAccess() == .signInRequired(OPDSSignInRequest(title: "Harbour", scheme: nil)))

        // Calibre-Web: only the Basic challenge.
        let basic = StubServer { _ in StubServer.Response(status: 401, headers: ["WWW-Authenticate": "Basic realm=\"Authentication Required\""], body: Data("Unauthorized Access".utf8)) }
        #expect(try await source(basic).checkAccess() == .signInRequired(OPDSSignInRequest()))
    }

    @Test func passwordGoesUpFrontOnlyForBasicServers() async throws {
        let credentials = PasswordCredentials(username: "keeper", password: "lamp-oil")
        let server = server(["/catalog": .atom(OPDSFixtures.atomRoot)])
        _ = try await source(server, credentials: InMemoryPasswordStore(credentials), scheme: .digest).root()
        _ = try await source(server, credentials: InMemoryPasswordStore(credentials), scheme: nil).root()
        #expect(server.requests.allSatisfy { $0.headers["authorization"] == nil }, "Digest and unknown: the transport answers the challenge")
        _ = try await source(server, credentials: InMemoryPasswordStore(credentials), scheme: .basic).root()
        #expect(server.requests.last?.headers["authorization"]?.hasPrefix("Basic ") == true)
    }

    @Test func readsThePasswordOnceUntilItIsRefused() async throws {
        let store = CountingPasswordStore(PasswordCredentials(username: "keeper", password: "lamp-oil"))
        let refused = Mutex(false)
        let server = StubServer { request in
            if refused.withLock({ $0 }) { return .atom("", status: 401) }
            return request.path == "/catalog/all" ? .atom(OPDSFixtures.atomBooks) : .atom(OPDSFixtures.atomRoot)
        }
        let source = source(server, credentials: store)
        _ = try await source.root()
        _ = try await source.feed(LibraryLink(rawValue: url(server, "/catalog/all")))
        _ = try await source.feed(LibraryLink(rawValue: url(server, "/catalog/all")))
        #expect(await store.loads == 1)
        refused.withLock { $0 = true }
        await #expect(throws: LibraryError.signedOut) { try await source.root() }
        refused.withLock { $0 = false }
        _ = try await source.root()
        #expect(await store.loads == 2, "a 401 makes the next request read the store again")
    }

    @Test func aDigestChallengeIsRecordedAsDigest() async throws {
        // Even when the Authentication Document only knows Basic.
        let digest = StubServer { _ in
            StubServer.Response(status: 401, headers: [
                "Content-Type": "application/opds-authentication+json",
                "WWW-Authenticate": "Digest realm=\"Harbour\", nonce=\"abc\", Basic realm=\"Harbour\"",
            ], body: Data(OPDSFixtures.authenticationDocument.utf8))
        }
        guard case .signInRequired(let request) = try await source(digest).checkAccess() else { Issue.record("expected a sign-in"); return }
        #expect(request.scheme == .digest)
        #expect(request.usernameLabel == "Email")

        let bearer = StubServer { _ in StubServer.Response(status: 401, headers: ["WWW-Authenticate": "Bearer"], body: Data()) }
        #expect(try await source(bearer).checkAccess() == .signInRequired(OPDSSignInRequest(scheme: nil)))
    }

    @Test func anEmptyOPDS2FeedHasNoBooks() async throws {
        let empty = #"{"metadata":{"title":"Search results"},"links":[{"rel":"self","href":"/v2/search?query=zzz","type":"application/opds+json"}]}"#
        let server = server(["/v2/search": .opds2(empty)])
        let feed = try await source(server, path: "/v2/home").feed(LibraryLink(rawValue: url(server, "/v2/search?query=zzz")))
        #expect(feed.title == "Search results")
        #expect(feed.books.isEmpty && feed.entries.isEmpty)
        // A lone publication is still read as one.
        let single = #"{"metadata":{"title":"Fog Signals"},"links":[{"rel":"http://opds-spec.org/acquisition","href":"/f.epub","type":"application/epub+zip"}]}"#
        let one = try OPDSJSONParser.parse(Data(single.utf8), url: server.baseURL)
        #expect(one.publications.map(\.title) == ["Fog Signals"])
    }

    @Test func aLaterPageWithoutATotalDoesNotCountItself() async throws {
        let lastPage = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Everything</title>
          <link rel="previous" href="/catalog/all?page=1" type="application/atom+xml;profile=opds-catalog"/>
          <entry><title>Salt Roads</title><id>2</id><link rel="http://opds-spec.org/acquisition" href="/get/2.epub" type="application/epub+zip"/></entry>
        </feed>
        """
        let server = server(["/catalog/all": .atom(lastPage), "/catalog": .atom(OPDSFixtures.atomBooksOnlyRoot)])
        let feed = try await source(server).feed(LibraryLink(rawValue: url(server, "/catalog/all?page=2")))
        #expect(feed.books.count == 1)
        #expect(feed.total == nil)
        // A feed with no other pages still counts itself.
        #expect(try await source(server).feed(LibraryLink(rawValue: url(server, "/catalog"))).total == 1)
    }

    @Test func anUnreadableSearchDescriptionIsTriedAgain() async throws {
        let broken = Mutex(true)
        let server = StubServer { request in
            switch request.path {
            case "/catalog": return .atom(OPDSFixtures.atomRoot)
            case "/catalog/opensearch.xml":
                return broken.withLock { $0 } ? .bytes("<html>Bad gateway</html>", type: "text/html") : .xml(OPDSFixtures.openSearchDescription)
            case "/catalog/search": return .atom(OPDSFixtures.atomBooksOnlyRoot)
            default: return .notFound
            }
        }
        let source = source(server)
        #expect(try await source.root().search == .books, "a failed lookup doesn't take search away")
        await #expect(throws: LibraryError.invalidResponse) { try await source.search("salt") }
        broken.withLock { $0 = false }
        #expect(try await source.search("salt").books.books.map(\.title) == ["Salt Roads"])
    }

    @Test func aDescriptionWithOnlyAWebPageMeansNoSearch() async throws {
        let htmlOnly = #"<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/"><Url type="text/html" template="/web?q={searchTerms}"/></OpenSearchDescription>"#
        let server = server(["/catalog": .atom(OPDSFixtures.atomRoot), "/catalog/opensearch.xml": .xml(htmlOnly)])
        let source = source(server)
        #expect(try await source.root().search == .unavailable)
        #expect(try await source.search("salt") == LibrarySearchResults(query: "salt"))
    }

    @Test func booksWithoutIDsGetDistinctOnes() throws {
        let feed = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Untitled</title>
          <entry><title>Untitled</title><link rel="http://opds-spec.org/image" href="/covers/a.jpg" type="image/jpeg"/></entry>
          <entry><title>Untitled</title><link rel="http://opds-spec.org/image" href="/covers/b.jpg" type="image/jpeg"/></entry>
        </feed>
        """
        let base = URL(string: "https://catalog.test/catalog")!
        let source = OPDSSource(catalogURL: base, transport: ServerTransport(server: base))
        let books = source.mapFeed(try OPDSAtomParser.parse(Data(feed.utf8), url: base), at: base).feed.books
        #expect(Set(books.map(\.id)).count == 2)
    }

    // MARK: Kavita's key

    @Test func findsKavitasKeyInItsAddress() {
        #expect(OPDSURLSecret.detect(in: URL(string: "http://nas:5000/api/opds/9fK2abcdXYZ0123456789qrstuvwx")!)?.value == "9fK2abcdXYZ0123456789qrstuvwx")
        #expect(OPDSURLSecret.detect(in: URL(string: "http://nas/kavita/api/opds/9fK2abcdXYZ01234")!)?.value == "9fK2abcdXYZ01234")
        #expect(OPDSURLSecret.detect(in: URL(string: "http://nas:3310/opds")!) == nil)
        #expect(OPDSURLSecret.detect(in: URL(string: "http://nas/api/opds/")!) == nil)
        #expect(OPDSURLSecret("short") == nil)
    }

    @Test func keepsKavitasKeyOutOfEverythingItHandsOut() async throws {
        let key = "9fK2abcdXYZ0123456789qrstuvwx"
        let series = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Alice</title>
          <link rel="next" href="/api/opds/\(key)/series/1?pageNumber=2" type="application/atom+xml;profile=opds-catalog"/>
          <entry><title>⭘ Alice - Alice</title><id>1</id>
            <link rel="http://opds-spec.org/image" type="image/jpeg" href="/api/image/chapter-cover?chapterId=1&amp;apiKey=\(key)"/>
            <link rel="http://opds-spec.org/acquisition/open-access" type="application/epub+zip" href="/api/opds/\(key)/series/1/volume/1/chapter/1/download/alice.epub"/>
          </entry>
          <entry><title>Elsewhere</title><id>2</id>
            <link rel="http://opds-spec.org/acquisition" type="application/epub+zip" href="https://cdn.example/\(key)/b.epub"/>
          </entry>
        </feed>
        """
        let server = StubServer { request in
            guard request.path.contains(key) || request.query["apiKey"] == key else { return .notFound }
            if request.path.hasSuffix("/series/1") { return .atom(series) }
            if request.path.hasSuffix(".epub") { return .bytes("PK-alice") }
            return .bytes("jpeg", type: "image/jpeg")
        }
        let source = source(server, path: "/api/opds/\(key)", scheme: nil, secret: OPDSURLSecret(key))
        let feed = try await source.feed(LibraryLink(rawValue: url(server, "/api/opds/{key}/series/1")))
        let alice = try #require(feed.books.first)
        let handedOut = [feed.next?.rawValue, alice.id.rawValue, alice.cover?.rawValue] + alice.files.map(\.id.rawValue)
        #expect(handedOut.allSatisfy { $0?.contains(key) != true })
        #expect(alice.files.first?.id.rawValue == url(server, "/api/opds/{key}/series/1/volume/1/chapter/1/download/alice.epub"))
        #expect(alice.title == "Alice")

        // Requests get the key back.
        #expect(try await source.cover(try #require(alice.cover), size: .full) == Data("jpeg".utf8))
        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-opds-\(UUID().uuidString)/alice.epub")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        try await source.download(try #require(alice.primaryFile), to: destination)
        #expect(try Data(contentsOf: destination) == Data("PK-alice".utf8))

        // A link to another host never gets the key back. (A catalog that
        // writes `{key}` itself makes a template, not a link.)
        let elsewhere = try #require(feed.books.last?.primaryFile)
        #expect(elsewhere.id.rawValue == "https://cdn.example/{key}/b.epub")
        await #expect(throws: LibraryError.invalidLink) { try await source.download(elsewhere, to: destination) }
    }

    // MARK: Security audit

    @Test func readsSchemeNamesNotWordsInParameters() {
        #expect(HTTPAuthScheme(challenge: #"Bearer realm="basic""#) == nil)
        #expect(HTTPAuthScheme(challenge: #"Bearer realm="digest", error="invalid""#) == nil)
        #expect(HTTPAuthScheme(challenge: #"Basic realm="Authentication Required""#) == .basic)
        #expect(HTTPAuthScheme(challenge: #"Digest realm="x", nonce="a,b", qop="auth", Basic realm="x""#) == .digest)
        #expect(HTTPAuthScheme(challenge: "basic") == .basic)
    }

    @Test func aDigestServerCanNotBeTalkedDownToBasic() async throws {
        // Someone answering at the server's home address offers only Basic,
        // or no challenge at all.
        for headers in [["WWW-Authenticate": "Basic realm=\"x\""], [:]] {
            let impostor = StubServer { _ in StubServer.Response(status: 401, headers: headers, body: Data()) }
            guard case .signInRequired(let request) = try await source(impostor, scheme: .digest).checkAccess() else {
                Issue.record("expected a sign-in"); return
            }
            #expect(request.scheme == .digest)
            #expect(impostor.requests.allSatisfy { $0.headers["authorization"] == nil })
        }
    }

    @Test func ignoresASignInDocumentOnAnotherHost() async throws {
        let elsewhere = StubServer { _ in .opds2(OPDSFixtures.authenticationDocument) }
        let catalog = StubServer { _ in
            StubServer.Response(status: 401, headers: [
                "Link": "<\(elsewhere.baseURL.absoluteString)/auth>; rel=\"http://opds-spec.org/auth/document\"",
                "WWW-Authenticate": "Basic realm=\"x\"",
            ], body: Data())
        }
        #expect(try await source(catalog).checkAccess() == .signInRequired(OPDSSignInRequest()))
        #expect(elsewhere.requests.isEmpty)
    }

    @Test func networkErrorsDropTheFailingURL() async throws {
        let key = "9fK2abcdXYZ0123456789qrstuvwx"
        let base = URL(string: "http://nas.invalid/api/opds/\(key)")!
        let source = OPDSSource(catalogURL: base, transport: FailingTransport(), secret: OPDSURLSecret(key))
        do {
            _ = try await source.root()
            Issue.record("expected a URLError")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
            #expect(error.failingURL == nil)
            #expect(!String(describing: error).contains(key))
        }
    }

    @Test func refusesUnsafeFilenames() {
        #expect(OPDSSource.filename(URL(string: "https://c.test/get/alice.epub")!) == "alice.epub")
        #expect(OPDSSource.filename(URL(string: "https://c.test/get/..%2F..%2Fx.epub")!) == nil)
        #expect(OPDSSource.filename(URL(string: "https://c.test/get/.hidden.epub")!) == nil)
        #expect(OPDSSource.filename(URL(string: "https://c.test/download/6/azw3/")!) == nil)
    }

    @Test func redactsTheKeyInEntryIDsAndBehindAProxyPrefix() throws {
        let key = "9fK2abcdXYZ0123456789qrstuvwx"
        #expect(OPDSURLSecret.detect(in: URL(string: "https://home.test/opds/api/opds/\(key)")!)?.value == key)
        let base = URL(string: "https://home.test/api/opds/\(key)")!
        let source = OPDSSource(catalogURL: base, transport: ServerTransport(server: base), secret: OPDSURLSecret(key))
        let feed = """
        <feed xmlns="http://www.w3.org/2005/Atom"><title>x</title><entry><title>Alice</title><id>urn:\(key):1</id>
          <link rel="http://opds-spec.org/acquisition" href="/a.epub" type="application/epub+zip"/></entry></feed>
        """
        let book = try #require(source.mapFeed(try OPDSAtomParser.parse(Data(feed.utf8), url: base), at: base).feed.books.first)
        #expect(book.id.rawValue == "urn:{key}:1")
    }

    @Test(arguments: ["collections/1?page=2", "file:///etc/passwd", "javascript:alert(1)", "https:///nohost", ""])
    func refusesLinksItDidNotMake(raw: String) async {
        let server = StubServer { _ in .notFound }
        await #expect(throws: LibraryError.invalidLink) { try await source(server).feed(LibraryLink(rawValue: raw)) }
    }

    @Test func tidiesKavitaTitles() {
        #expect(OPDSSource.title("⭘ Alice's Adventures in Wonderland - Alice's Adventures in Wonderland") == "Alice's Adventures in Wonderland")
        #expect(OPDSSource.title("◔ Moby Dick") == "Moby Dick")
        #expect(OPDSSource.title("Hither - Thither") == "Hither - Thither")
    }

    @Test func keepsPublishedDatesAsSentUnlessTimestamped() {
        #expect(OPDSSource.date("2008-06-27T08:08:08Z") == "2008-06-27")
        #expect(OPDSSource.date("2004-10-02T00:00:00+00:00") == "2004-10-02")
        #expect(OPDSSource.date("1998") == "1998")
    }
}
