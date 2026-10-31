import Foundation
@testable import OctavoKit
import Testing

/// Runs against a real BookOrbit seeded by `dev/bookorbit/seed.sh`. Skipped
/// unless all three variables are set:
///
///     OCTAVO_BOOKORBIT_URL=http://localhost:3300 OCTAVO_BOOKORBIT_USER=octavo \
///     OCTAVO_BOOKORBIT_PASS=OctavoDev1 swift test --filter BookOrbitLiveTests
///
/// BookOrbit allows 5 logins a minute per IP and this suite uses 3, so wait a
/// minute between runs if one fails with HTTP 429.
@Suite(.serialized, .enabled(if: LiveServer.isConfigured, "Set OCTAVO_BOOKORBIT_URL, OCTAVO_BOOKORBIT_USER and OCTAVO_BOOKORBIT_PASS"))
struct BookOrbitLiveTests {
    @Test func listsDownloadsAndSyncsProgress() async throws {
        let store = InMemoryBookOrbitTokenStore()
        let client = BookOrbitClient(baseURL: LiveServer.url, tokenStore: store, deviceLabel: "OctavoKit live tests")

        let user = try await client.login(username: LiveServer.user, password: LiveServer.pass)
        #expect(user.username == LiveServer.user)
        #expect(await store.load()?.refreshTransport == .body)

        #expect(try await client.libraries().contains { $0.name == "Spike" })
        let spike = try #require(try await client.collections().first { $0.name == "Spike" })
        let page = try await client.collectionBooks(collectionID: spike.id)
        #expect(page.items.count == spike.bookCount)
        let listed = try #require(page.items.first { $0.primaryFile?.format == "epub" })

        let book = try await client.book(id: listed.id)
        #expect(book.title == listed.title)
        #expect(!book.authors.isEmpty)
        let file = try #require(book.primaryFile)

        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-live-\(UUID().uuidString)/\(file.id).epub")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        try await client.download(fileID: file.id, to: destination)
        let epub = try Data(contentsOf: destination)
        #expect(epub.count == file.sizeBytes)
        #expect(epub.prefix(2) == Data("PK".utf8))

        // Write a position, read it back, then put back whatever was there.
        let previous = try await client.progress(fileID: file.id)
        let position = ReadingPosition(cfi: "epubcfi(/6/4!/4/2/1:0)", fraction: Double(Int.random(in: 1000...9000)) / 10_000)
        try await client.saveProgress(position, fileID: file.id)
        let saved = try #require(try await client.progress(fileID: file.id))
        #expect(saved.position.cfi == position.cfi)
        #expect(abs(saved.position.fraction - position.fraction) < 1e-6)
        #expect(saved.position.pageNumber == nil)
        #expect(saved.updatedAt != nil)
        if let previous { try await client.saveProgress(previous.position, fileID: file.id) }

        // An expired access token is refreshed with the stored refresh token.
        var stale = try #require(await store.load())
        stale.accessToken = "expired"
        let staleStore = InMemoryBookOrbitTokenStore(stale)
        let refreshing = BookOrbitClient(baseURL: LiveServer.url, tokenStore: staleStore)
        #expect(try await refreshing.collections().contains { $0.id == spike.id })
        let refreshed = try #require(await staleStore.load())
        #expect(refreshed.accessToken != "expired")
        #expect(refreshed.refreshToken != stale.refreshToken)
    }

    /// The pre-3.0 path: refresh token from `Set-Cookie`, replayed by hand.
    @Test func refreshesWithCookieCredentials() async throws {
        let store = InMemoryBookOrbitTokenStore()
        let client = BookOrbitClient(
            baseURL: LiveServer.url, tokenStore: store, deviceLabel: "OctavoKit live tests",
            configuration: .default, requestsNativeCredentials: false
        )
        try await client.login(username: LiveServer.user, password: LiveServer.pass)
        var stale = try #require(await store.load())
        #expect(stale.refreshTransport == .cookie)
        #expect(stale.refreshToken?.count == 64)

        stale.accessToken = "expired"
        let staleStore = InMemoryBookOrbitTokenStore(stale)
        let refreshing = BookOrbitClient(baseURL: LiveServer.url, tokenStore: staleStore)
        #expect(try await !refreshing.libraries().isEmpty)
        let refreshed = try #require(await staleStore.load())
        #expect(refreshed.refreshTransport == .cookie)
        #expect(refreshed.refreshToken != stale.refreshToken)
    }

    /// Records what URLSession's own cookie jar does with BookOrbit's refresh
    /// cookie (what a cookie-jar client would rely on). The client doesn't
    /// use the jar; this documents the platform.
    @Test func urlSessionCookieJarKeepsRefreshCookie() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration)
        let api = LiveServer.url.appending(path: "api/v1/auth")

        var login = URLRequest(url: api.appending(path: "login"))
        login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONEncoder().encode(["username": LiveServer.user, "password": LiveServer.pass])
        let (_, loginResponse) = try await session.data(for: login)
        #expect((loginResponse as? HTTPURLResponse)?.statusCode == 200)

        let refreshURL = api.appending(path: "refresh")
        let cookie = try #require(configuration.httpCookieStorage?.cookies(for: refreshURL)?.first { $0.name == "refresh_token" })
        // BookOrbit sets `secure: 'auto'`: Secure only when the request was HTTPS.
        #expect(cookie.isSecure == (LiveServer.url.scheme == "https"))
        #expect(cookie.isHTTPOnly)
        #expect(cookie.path == "/api/v1/auth")
        #expect(cookie.sameSitePolicy == .sameSiteStrict)

        var refresh = URLRequest(url: refreshURL)
        refresh.httpMethod = "POST"
        refresh.setValue("application/json", forHTTPHeaderField: "Content-Type")
        refresh.httpBody = Data("{}".utf8)
        let (_, refreshResponse) = try await session.data(for: refresh)
        #expect((refreshResponse as? HTTPURLResponse)?.statusCode == 200)
    }
}

enum LiveServer {
    private static let environment = ProcessInfo.processInfo.environment

    static var isConfigured: Bool {
        ["OCTAVO_BOOKORBIT_URL", "OCTAVO_BOOKORBIT_USER", "OCTAVO_BOOKORBIT_PASS"].allSatisfy { environment[$0]?.isEmpty == false }
    }

    static var url: URL { URL(string: environment["OCTAVO_BOOKORBIT_URL"]!)! }
    static var user: String { environment["OCTAVO_BOOKORBIT_USER"]! }
    static var pass: String { environment["OCTAVO_BOOKORBIT_PASS"]! }
}
