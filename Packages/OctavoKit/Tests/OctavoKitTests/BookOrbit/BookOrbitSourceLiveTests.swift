import Foundation
@testable import OctavoKit
import Synchronization
import Testing

/// `BookOrbitSource` against a real BookOrbit seeded by `dev/bookorbit/seed.sh`
/// (the five sample books in a "Spike" collection). Gated like
/// `BookOrbitLiveTests`:
///
///     OCTAVO_BOOKORBIT_URL=http://localhost:3300 OCTAVO_BOOKORBIT_USER=octavo \
///     OCTAVO_BOOKORBIT_PASS=OctavoDev1 swift test --filter BookOrbitSourceLiveTests
///
/// Signs in once for the whole suite. The only write is a smart scope named
/// "Octavo live test", created and deleted by `opensCollectionsAndSmartScopes`.
/// The seed has no series, so the series test only checks the list decodes
/// until the server has one.
@Suite(.serialized, .enabled(if: LiveServer.isConfigured, "Set OCTAVO_BOOKORBIT_URL, OCTAVO_BOOKORBIT_USER and OCTAVO_BOOKORBIT_PASS"))
struct BookOrbitSourceLiveTests {
    private static let signedIn = Task<BookOrbitCredentials, any Error> {
        let store = InMemoryBookOrbitTokenStore()
        try await BookOrbitClient(baseURL: LiveServer.url, tokenStore: store, deviceLabel: "OctavoKit live tests")
            .login(username: LiveServer.user, password: LiveServer.pass)
        guard let credentials = await store.load() else { throw BookOrbitError.notSignedIn }
        return credentials
    }

    private func source(pageSize: Int = 50) async throws -> BookOrbitSource {
        let store = InMemoryBookOrbitTokenStore(try await Self.signedIn.value)
        return BookOrbitSource(client: BookOrbitClient(baseURL: LiveServer.url, tokenStore: store), pageSize: pageSize)
    }

    /// Every page of a list, following `next`.
    private func everything(_ source: BookOrbitSource, from link: LibraryLink) async throws -> LibraryFeed {
        var feed = try await source.feed(link)
        var next = feed.next
        while let link = next {
            let page = try await source.feed(link)
            feed.books += page.books
            feed.entries += page.entries
            next = page.next
        }
        return feed
    }

    private func book(titled title: String, in source: BookOrbitSource) async throws -> LibraryBook {
        let all = try await everything(source, from: try await source.root().chips[0].link)
        return try #require(all.books.first { $0.title == title })
    }

    @Test func browsesAllBooksPageByPage() async throws {
        let source = try await source(pageSize: 2)
        let root = try await source.root()
        #expect(root.chips.map(\.title) == ["All", "Collections", "Series", "Authors"])

        let first = try await source.feed(root.chips[0].link)
        let total = try #require(first.total)
        #expect(total >= 5)
        #expect(first.books.count == 2)
        #expect(first.next != nil)
        let all = try await everything(source, from: root.chips[0].link)
        #expect(all.books.count == total)
        #expect(Set(all.books.map(\.id)).count == total)
        #expect(all.books.map(\.title) == all.books.map(\.title).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(all.books.allSatisfy { $0.primaryFile?.format != nil && $0.cover != nil })

        let recent = try await everything(source, from: try #require(root.recentlyAdded))
        #expect(Set(recent.books.map(\.id)) == Set(all.books.map(\.id)))
    }

    @Test func opensCollectionsAndSmartScopes() async throws {
        let source = try await source()
        let name = "Octavo live test"
        for leftover in try await smartScopes().filter({ $0.name == name }) { try await deleteSmartScope(leftover.id) }

        let scopeID = try await createSmartScope(name: name, titleContains: "Pride")
        do {
            let collections = try await source.feed(try await source.root().chips[1].link)
            let spike = try #require(collections.entries.first { $0.kind == .collection && $0.title == "Spike" })
            let scope = try #require(collections.entries.first { $0.kind == .smartCollection && $0.title == name })
            #expect(collections.entries.firstIndex(of: spike)! < collections.entries.firstIndex(of: scope)!)

            let spikeBooks = try await everything(source, from: spike.link)
            #expect(spikeBooks.books.count == spike.count)
            #expect(spikeBooks.books.count >= 5)

            let scopeBooks = try await everything(source, from: scope.link)
            #expect(scopeBooks.books.map(\.title) == ["Pride and Prejudice"])
        } catch {
            try? await deleteSmartScope(scopeID)
            throw error
        }
        try await deleteSmartScope(scopeID)
        #expect(try await smartScopes().contains { $0.id == scopeID } == false)
    }

    @Test func listsAuthorsAToZAndTheirBooks() async throws {
        let source = try await source(pageSize: 2)
        let authors = try await everything(source, from: try await source.root().chips[3].link)
        let sortNames = authors.entries.map { $0.sortName ?? $0.title }
        #expect(sortNames == sortNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(authors.entries.count == authors.total)

        let austen = try #require(authors.entries.first { $0.title == "Jane Austen" })
        #expect(austen.sortName == "Austen, Jane")
        #expect(austen.kind == .author)
        let books = try await everything(source, from: austen.link)
        #expect(books.books.map(\.title).contains("Pride and Prejudice"))
        #expect(books.books.count == austen.count)
    }

    @Test func listsSeriesInReadingOrder() async throws {
        let source = try await source()
        let series = try await everything(source, from: try await source.root().chips[2].link)
        #expect(series.entries.count == series.total)
        // The seed has no series; this part runs once the server has one.
        guard let first = series.entries.first else { return }
        #expect(first.kind == .series)
        let books = try await everything(source, from: first.link)
        #expect(books.books.count == first.count)
        let positions = books.books.compactMap(\.series?.position)
        #expect(positions == positions.sorted())
    }

    @Test func searchesBooksAndAuthors() async throws {
        let source = try await source()

        let jane = try await source.search("jane")
        #expect(jane.books.books.map(\.title).contains("Pride and Prejudice"))
        #expect(jane.authors.map(\.title).contains("Jane Austen"))
        let austen = try #require(jane.authors.first { $0.title == "Jane Austen" })
        #expect(try await source.feed(austen.link).books.map(\.title).contains("Pride and Prejudice"))

        let holmes = try await source.search("holmes")
        #expect(holmes.books.books.first?.title == "The Adventures of Sherlock Holmes")

        let short = try await source.search("j")
        #expect(short.books.books.isEmpty)
    }

    @Test func detailsLinkBackIntoTheLibrary() async throws {
        let source = try await source()
        let listed = try await book(titled: "Pride and Prejudice", in: source)

        let details = try await source.details(for: listed)
        #expect(details.book.id == listed.id)
        #expect(details.book.primaryFile?.filename?.hasSuffix(".epub") == true)
        #expect(details.addedAt != nil)
        #expect(details.language == "en")
        let author = try #require(details.authors.first)
        #expect(author.title == "Jane Austen")
        #expect(try await source.feed(author.link).books.contains { $0.id == listed.id })
        let spike = try #require(details.collections.first { $0.title == "Spike" })
        #expect(try await everything(source, from: spike.link).books.contains { $0.id == listed.id })
    }

    @Test func fetchesCoversAndDownloadsWithProgress() async throws {
        let source = try await source()
        let listed = try await book(titled: "Pride and Prejudice", in: source)
        let cover = try #require(listed.cover)
        #expect(cover.version != nil)

        let thumbnail = try await source.cover(cover, size: .thumbnail)
        let full = try await source.cover(cover, size: .full)
        #expect(thumbnail.prefix(2) == Data([0xFF, 0xD8]))
        #expect(full.prefix(2) == Data([0xFF, 0xD8]))
        #expect(full.count > thumbnail.count)

        let file = try #require(listed.primaryFile)
        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-live-\(UUID().uuidString)/book.epub")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        let reported = Mutex<[Double]>([])
        try await source.download(file, to: destination) { value in reported.withLock { $0.append(value) } }

        let epub = try Data(contentsOf: destination)
        #expect(epub.count == file.sizeBytes)
        #expect(epub.prefix(2) == Data("PK".utf8))
        let values = reported.withLock { $0 }
        #expect(values.count > 2)
        #expect(values == values.sorted())
        #expect(values.last == 1)
    }

    // MARK: - Smart scope fixture (raw API; the client has no write calls for scopes)

    private struct Scope: Decodable { var id: Int; var name: String }

    private func api(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: LiveServer.url.appending(path: "api/v1/" + path))
        request.httpMethod = method
        request.setValue("Bearer \(try await Self.signedIn.value.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw BookOrbitError.http(status: status, message: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    private func smartScopes() async throws -> [Scope] {
        try JSONDecoder().decode([Scope].self, from: try await api("GET", "smart-scopes"))
    }

    private func createSmartScope(name: String, titleContains text: String) async throws -> Int {
        let data = try await api("POST", "smart-scopes", body: [
            "name": name,
            "icon": "Sparkles",
            "filter": ["type": "group", "join": "AND", "rules": [["type": "rule", "field": "title", "operator": "contains", "value": text]]],
            "defaultSort": [["field": "title", "dir": "asc"]],
        ])
        return try JSONDecoder().decode(Scope.self, from: data).id
    }

    private func deleteSmartScope(_ id: Int) async throws {
        _ = try await api("DELETE", "smart-scopes/\(id)")
    }
}
