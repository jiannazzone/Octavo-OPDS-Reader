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

private func source(_ server: StubServer, path: String = "/catalog", credentials: OPDSCredentials? = nil) -> OPDSSource {
    OPDSSource(
        catalogURL: server.baseURL.appending(path: path),
        session: URLSession(configuration: server.configuration),
        credentials: InMemoryOPDSCredentialStore(credentials)
    )
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

    @Test func picksTheFeedURLFromAnOpenSearchDescription() {
        let template = OpenSearchDescriptionParser.template(in: Data(OPDSFixtures.openSearchDescription.utf8), url: base)
        #expect(template?.template == "/catalog/search?q={searchTerms}&page={startPage?}")
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
        let credentials = OPDSCredentials(username: "keeper", password: "lamp-oil")
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
        let source = source(catalog, credentials: credentials)
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
        #expect(try await source(linked).checkAccess() == .signInRequired(OPDSSignInRequest(title: "Harbour", supportsBasic: false)))

        // Calibre-Web: only the Basic challenge.
        let basic = StubServer { _ in StubServer.Response(status: 401, headers: ["WWW-Authenticate": "Basic realm=\"Authentication Required\""], body: Data("Unauthorized Access".utf8)) }
        #expect(try await source(basic).checkAccess() == .signInRequired(OPDSSignInRequest()))
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
