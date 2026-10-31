import Foundation
@testable import OctavoKit
import Synchronization
import Testing

private let userJSON = #"{"id":1,"username":"octavo","name":"Octavo Dev","isSuperuser":true,"permissions":["*"]}"#
private let refreshToken1 = String(repeating: "a", count: 64)
private let refreshToken2 = String(repeating: "b", count: 64)

private func signedIn(_ server: StubServer, accessToken: String = "access-1", transport: BookOrbitCredentials.RefreshTransport = .body) -> BookOrbitClient {
    let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(
        accessToken: accessToken, refreshToken: refreshToken1, refreshTransport: transport, sessionID: 7
    ))
    return BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)
}

struct BookOrbitAuthTests {
    @Test func logsInAsNativeClient() async throws {
        let server = StubServer { request in
            .json(#"""
            {"accessToken":"access-1","accessTokenExpiresAt":"2026-10-31T15:58:53.000Z",
             "refreshToken":"\#(refreshToken1)","refreshTokenExpiresAt":"2026-11-07T15:43:53.117Z",
             "sessionId":2,"user":\#(userJSON)}
            """#)
        }
        let store = InMemoryBookOrbitTokenStore()
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, deviceLabel: "Test iPhone", configuration: server.configuration)

        let user = try await client.login(username: "octavo", password: "OctavoDev1")

        #expect(user.username == "octavo")
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/auth/login")
        #expect(request.json?["clientKind"] as? String == "native")
        #expect(request.json?["deviceLabel"] as? String == "Test iPhone")
        let stored = try #require(await store.load())
        #expect(stored.accessToken == "access-1")
        #expect(stored.refreshToken == refreshToken1)
        #expect(stored.refreshTransport == .body)
        #expect(stored.sessionID == 2)
        #expect(stored.refreshTokenExpiresAt != nil)
    }

    @Test func fallsBackToRefreshCookieOnPre3Servers() async throws {
        let server = StubServer { request in
            if request.json?["clientKind"] != nil {
                return .json(400, #"{"statusCode":400,"message":["property clientKind should not exist","property deviceLabel should not exist"]}"#)
            }
            return .json(#"{"accessToken":"access-1","user":\#(userJSON)}"#, headers: [
                "Set-Cookie": "refresh_token=\(refreshToken1); Max-Age=604799; Path=/api/v1/auth; HttpOnly; SameSite=Strict",
            ])
        }
        let store = InMemoryBookOrbitTokenStore()
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)

        try await client.login(username: "octavo", password: "OctavoDev1")

        #expect(server.requests.count == 2)
        #expect(server.requests.last?.json?["clientKind"] == nil)
        let stored = try #require(await store.load())
        #expect(stored.refreshTransport == .cookie)
        #expect(stored.refreshToken == refreshToken1)
        #expect(stored.refreshTokenExpiresAt != nil)
    }

    @Test func doesNotRetryRejectedPassword() async throws {
        let server = StubServer { _ in .json(401, #"{"statusCode":401,"message":"Invalid credentials"}"#) }
        let client = BookOrbitClient(baseURL: server.baseURL, configuration: server.configuration)

        await #expect(throws: BookOrbitError.http(status: 401, message: "Invalid credentials")) {
            try await client.login(username: "octavo", password: "wrong")
        }
        #expect(server.requests.count == 1)
    }

    @Test func requiresSignIn() async {
        let server = StubServer { _ in .json("[]") }
        let client = BookOrbitClient(baseURL: server.baseURL, configuration: server.configuration)
        await #expect(throws: BookOrbitError.notSignedIn) { try await client.libraries() }
        #expect(server.requests.isEmpty)
    }

    @Test func refreshesOnUnauthorizedAndRetries() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/auth/refresh":
                return .json(#"""
                {"accessToken":"access-2","accessTokenExpiresAt":"2026-10-31T16:13:53.000Z",
                 "refreshToken":"\#(refreshToken2)","refreshTokenExpiresAt":"2026-11-07T15:58:53.117Z","sessionId":7}
                """#)
            default:
                return request.headers["authorization"] == "Bearer access-2" ? .json(#"[{"id":1,"name":"Spike"}]"#) : .unauthorized
            }
        }
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: refreshToken1))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)

        let libraries = try await client.libraries()

        #expect(libraries.map(\.name) == ["Spike"])
        #expect(server.requests.map(\.path) == ["/api/v1/libraries", "/api/v1/auth/refresh", "/api/v1/libraries"])
        #expect(server.requests(to: "/api/v1/auth/refresh").first?.json?["refreshToken"] as? String == refreshToken1)
        #expect(server.requests(to: "/api/v1/auth/refresh").first?.headers["cookie"] == nil)
        let stored = try #require(await store.load())
        #expect(stored.accessToken == "access-2")
        #expect(stored.refreshToken == refreshToken2)
    }

    @Test func concurrentUnauthorizedRequestsShareOneRefresh() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/auth/refresh":
                Thread.sleep(forTimeInterval: 0.05)
                return .json(#"{"accessToken":"access-2","refreshToken":"\#(refreshToken2)"}"#)
            default:
                return request.headers["authorization"] == "Bearer access-2" ? .json("[]") : .unauthorized
            }
        }
        let client = signedIn(server)

        try await withThrowingTaskGroup { group in
            for _ in 0..<8 { group.addTask { _ = try await client.collections() } }
            try await group.waitForAll()
        }

        #expect(server.requests(to: "/api/v1/auth/refresh").count == 1)
    }

    @Test func rejectedRefreshEndsSession() async throws {
        let server = StubServer { _ in .unauthorized }
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: refreshToken1))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)

        await #expect(throws: BookOrbitError.sessionExpired) { try await client.libraries() }
        #expect(await store.load() == nil)
        await #expect(throws: BookOrbitError.notSignedIn) { try await client.libraries() }
    }

    @Test func failedRefreshKeepsCredentialsWhenServerErrors() async throws {
        let server = StubServer { request in
            request.path == "/api/v1/auth/refresh" ? .json(503, #"{"statusCode":503,"message":"Starting up"}"#) : .unauthorized
        }
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: refreshToken1))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)

        await #expect(throws: BookOrbitError.http(status: 503, message: "Starting up")) { try await client.libraries() }
        #expect(await store.load()?.refreshToken == refreshToken1)
    }

    @Test func refreshesWithCookieOnPre3Servers() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/auth/refresh":
                guard request.headers["cookie"] == "refresh_token=\(refreshToken1)" else { return .unauthorized }
                return .json(#"{"accessToken":"access-2"}"#, headers: [
                    "Set-Cookie": "refresh_token=\(refreshToken2); Max-Age=604799; Path=/api/v1/auth; HttpOnly; SameSite=Strict",
                ])
            default:
                return request.headers["authorization"] == "Bearer access-2" ? .json("[]") : .unauthorized
            }
        }
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: refreshToken1, refreshTransport: .cookie))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)

        _ = try await client.libraries()

        let refresh = try #require(server.requests(to: "/api/v1/auth/refresh").first)
        #expect(refresh.json?.isEmpty == true)
        let stored = try #require(await store.load())
        #expect(stored.accessToken == "access-2")
        #expect(stored.refreshToken == refreshToken2)
        #expect(stored.refreshTransport == .cookie)
    }

    @Test func signOutForgetsCredentials() async throws {
        let server = StubServer { _ in .json("[]") }
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1"))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)
        try await client.signOut()
        #expect(await store.load() == nil)
        await #expect(throws: BookOrbitError.notSignedIn) { try await client.libraries() }
    }
}

struct BookOrbitEndpointTests {
    @Test func sendsBearerTokenAndPagesCollectionBooks() async throws {
        let server = StubServer { _ in
            .json(#"{"items":[{"id":3,"title":"Moby Dick; Or, The Whale","authors":["Herman Melville"],"files":[{"id":3,"format":"epub","role":"primary"}]}],"total":5,"page":2,"size":1}"#)
        }
        let client = signedIn(server)

        let page = try await client.collectionBooks(collectionID: 1, page: 2, size: 1)

        #expect(page.items.first?.title == "Moby Dick; Or, The Whale")
        let request = try #require(server.requests.first)
        #expect(request.path == "/api/v1/collections/1/books")
        #expect(request.query == ["page": "2", "size": "1"])
        #expect(request.headers["authorization"] == "Bearer access-1")
    }

    @Test func keepsBasePathOfProxiedServers() async throws {
        let server = StubServer { _ in .json(#"{"id":1,"title":"Frankenstein"}"#) }
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1"))
        let client = BookOrbitClient(baseURL: server.baseURL.appending(path: "bookorbit"), tokenStore: store, configuration: server.configuration)

        _ = try await client.book(id: 1)

        #expect(server.requests.first?.path == "/bookorbit/api/v1/books/1")
    }

    @Test func reportsServerErrors() async throws {
        let server = StubServer { _ in .json(404, #"{"statusCode":404,"message":"Book not found"}"#) }
        let client = signedIn(server)
        await #expect(throws: BookOrbitError.http(status: 404, message: "Book not found")) { try await client.book(id: 99) }
    }

    @Test func downloadsFileToDestination() async throws {
        let epub = Data("PK\u{3}\u{4}fake epub".utf8)
        let server = StubServer { request in
            request.path == "/api/v1/books/files/4/serve"
                ? StubServer.Response(status: 200, headers: ["Content-Type": "application/epub+zip"], body: epub)
                : .json(404, #"{"statusCode":404,"message":"File not found"}"#)
        }
        let client = signedIn(server)
        let directory = FileManager.default.temporaryDirectory.appending(path: "octavo-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "books/4.epub")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination)

        let saved = try await client.download(fileID: 4, to: destination)

        #expect(saved == destination)
        #expect(try Data(contentsOf: destination) == epub)
        await #expect(throws: BookOrbitError.http(status: 404, message: "File not found")) {
            try await client.download(fileID: 5, to: directory.appending(path: "5.epub"))
        }
    }

    @Test func downloadRefreshesOnUnauthorized() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/auth/refresh":
                return .json(#"{"accessToken":"access-2","refreshToken":"\#(refreshToken2)"}"#)
            default:
                guard request.headers["authorization"] == "Bearer access-2" else { return .unauthorized }
                return StubServer.Response(status: 200, headers: [:], body: Data("PK".utf8))
            }
        }
        let client = signedIn(server)
        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-tests-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await client.download(fileID: 1, to: destination)

        #expect(try Data(contentsOf: destination) == Data("PK".utf8))
    }

    @Test func readsProgress() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/books/files/1/progress":
                return .json(#"{"cfi":"epubcfi(/6/2!/4/2)","pageNumber":null,"percentage":0.3082087,"textUpdatedAt":"2026-10-31T15:46:59.851Z"}"#)
            default:
                return .json(#"{"cfi":null,"pageNumber":null,"percentage":0,"textUpdatedAt":null}"#)
            }
        }
        let client = signedIn(server)

        let progress = try #require(try await client.progress(fileID: 1))
        #expect(progress.position.cfi == "epubcfi(/6/2!/4/2)")
        #expect(abs(progress.position.fraction - 0.003082087) < 1e-12)
        #expect(try await client.progress(fileID: 2) == nil)
    }

    @Test func savesProgressAsPercentage() async throws {
        let server = StubServer { _ in StubServer.Response(status: 201, headers: [:], body: Data()) }
        let client = signedIn(server)

        try await client.saveProgress(ReadingPosition(cfi: "epubcfi(/6/14!/4/2/10/1:120)", fraction: 0.375), fileID: 3)

        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/books/files/3/progress")
        #expect(request.headers["content-type"] == "application/json")
        #expect(request.json?["cfi"] as? String == "epubcfi(/6/14!/4/2/10/1:120)")
        #expect(request.json?["percentage"] as? Double == 37.5)
        #expect(request.json?["pageNumber"] == nil)
    }
}
