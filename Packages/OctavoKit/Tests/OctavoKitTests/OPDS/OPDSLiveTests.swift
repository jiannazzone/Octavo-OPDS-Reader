import Foundation
@testable import OctavoKit
import Testing

/// Against the local servers in `dev/opds/` (README there): started and
/// seeded, then
///
///     OCTAVO_OPDS_LIVE=1 swift test --filter OPDSLiveTests
///
/// Each server's address can be moved with `OCTAVO_OPDS_<NAME>_URL`. Nothing
/// is written to the servers.
@Suite(.serialized, .enabled(if: LiveOPDS.isEnabled, "Set OCTAVO_OPDS_LIVE=1 with dev/opds running"))
struct OPDSLiveTests {
    @Test(arguments: LiveOPDS.Server.allCases)
    func browsesSearchesAndDownloads(server: LiveOPDS.Server) async throws {
        let source = try await server.source()
        let root = try await source.root()
        #expect(root.chips.count >= (server == .komga2 ? 4 : 5), "\(server)")
        #expect(root.search == .books)

        // Opens on the whole library, not the first chip.
        let start = try #require(root.startChip, "\(server)")
        let startTitle = root.chips.first { $0.link == start }?.title
        #expect(startTitle == server.startChipTitle)
        #expect(root.recentlyAdded != nil)

        let book = try await findBook(titled: "Alice", from: source, startingAt: start)
        #expect(book.authors == ["Lewis Carroll"])
        let file = try #require(book.primaryFile)
        #expect(file.format == "epub", "EPUB first when a book has several formats")

        let cover = try #require(book.cover)
        let thumbnail = try await source.cover(cover, size: .thumbnail)
        #expect(isImage(thumbnail))

        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-opds-live-\(UUID().uuidString)/alice.epub")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        let progress = ProgressLog()
        try await source.download(file, to: destination) { progress.append($0) }
        let bytes = try Data(contentsOf: destination)
        #expect(bytes.starts(with: Data("PK".utf8)), "an EPUB is a zip")

        let details = try await source.details(for: book)
        #expect(details.book.title == book.title)

        let results = try await source.search("alice")
        #expect(!(results.books.books.isEmpty && results.books.entries.isEmpty), "\(server)")
    }

    @Test(arguments: LiveOPDS.Server.allCases)
    func asksForSignInOnlyWhenNeeded(server: LiveOPDS.Server) async throws {
        let open = try await server.source(signedIn: false).checkAccess()
        switch (server.needsSignIn, open) {
        case (false, .open):
            break
        case (true, .signInRequired(let request)):
            #expect(request.supportsBasic)
            if server == .komga || server == .komga2 {
                // From Komga's OPDS Authentication Document.
                #expect(request.usernameLabel == "Email")
            }
        default:
            Issue.record("\(server): \(open)")
        }
        if server.needsSignIn {
            await #expect(throws: LibraryError.signedOut) { try await server.source(signedIn: false).root() }
            #expect(try await server.source().checkAccess() == .open(title: try await server.source().root().title))
        }
    }

    @Test func calibreWebNamesKindleFilesByTitle() async throws {
        let source = try await LiveOPDS.Server.calibreWeb.source()
        let root = try await source.root()
        let book = try await findBook(titled: "The Time Machine", from: source, startingAt: try #require(root.startChip))
        // AZW3 and MOBI share one media type there, and FB2 is sent as fb2+zip.
        #expect(book.files.map(\.format) == ["azw3", "mobi", "fb2"])
        #expect(book.primaryFile?.format == "azw3")
    }

    /// Walks down from `link` (first entry each time, then the next page)
    /// until a book whose title starts with `title` turns up.
    private func findBook(titled title: String, from source: OPDSSource, startingAt link: LibraryLink, depth: Int = 0) async throws -> LibraryBook {
        var page: LibraryLink? = link
        var visited = 0
        while let current = page, visited < 10 {
            visited += 1
            let feed = try await source.feed(current)
            if let book = feed.books.first(where: { $0.title.hasPrefix(title) }) { return book }
            if depth < 3 {
                for entry in feed.entries {
                    if let book = try? await findBook(titled: title, from: source, startingAt: entry.link, depth: depth + 1) { return book }
                }
            }
            page = feed.next
        }
        throw LibraryError.notFound
    }

    private func isImage(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xD8]) || data.starts(with: [0x89, 0x50, 0x4E, 0x47]) || data.starts(with: Data("RIFF".utf8))
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func append(_ value: Double) { lock.withLock { values.append(value) } }
}

enum LiveOPDS {
    private static let environment = ProcessInfo.processInfo.environment

    static var isEnabled: Bool { environment["OCTAVO_OPDS_LIVE"] == "1" }

    enum Server: String, CaseIterable, CustomStringConvertible, Sendable {
        case calibreWeb, cops, komga, komga2, kavita

        var description: String { rawValue }

        var needsSignIn: Bool { self == .calibreWeb || self == .komga || self == .komga2 }

        var startChipTitle: String {
            switch self {
            case .calibreWeb: "Alphabetical Books"
            case .cops: "All books"
            case .komga: "All series"
            case .komga2: "Browse"
            case .kavita: "All Libraries"
            }
        }

        private func base(_ key: String, _ fallback: String) -> URL {
            URL(string: environment["OCTAVO_OPDS_\(key)_URL"] ?? fallback)!
        }

        var credentials: PasswordCredentials? {
            switch self {
            case .calibreWeb: PasswordCredentials(username: "octavo", password: "OctavoDev1")
            case .komga, .komga2: PasswordCredentials(username: "octavo@example.com", password: "OctavoDev1")
            case .cops, .kavita: nil
            }
        }

        func catalogURL() async throws -> URL {
            switch self {
            case .calibreWeb: base("CALIBRE_WEB", "http://127.0.0.1:3310").appending(path: "opds")
            case .cops: base("COPS", "http://127.0.0.1:3320").appending(path: "feed")
            case .komga: base("KOMGA", "http://127.0.0.1:3330").appending(path: "opds/v1.2/catalog")
            case .komga2: base("KOMGA", "http://127.0.0.1:3330").appending(path: "opds/v2/catalog")
            case .kavita: try await LiveOPDS.kavitaCatalog(base("KAVITA", "http://127.0.0.1:3340"))
            }
        }

        func source(signedIn: Bool = true) async throws -> OPDSSource {
            OPDSSource(
                catalogURL: try await catalogURL(),
                credentials: InMemoryPasswordStore(signedIn ? credentials : nil)
            )
        }
    }

    /// Kavita's OPDS address carries the account's API key, which its REST
    /// login returns (the same key its settings page shows).
    static func kavitaCatalog(_ base: URL) async throws -> URL {
        var request = URLRequest(url: base.appending(path: "api/Account/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": "octavo", "password": "OctavoDev1"])
        let (data, _) = try await URLSession(configuration: .ephemeral).data(for: request)
        struct Login: Decodable { var apiKey: String }
        let key = try JSONDecoder().decode(Login.self, from: data).apiKey
        return base.appending(path: "api/opds/\(key)")
    }
}
