import Foundation
import OctavoKit
import Synchronization
import Testing

struct BookOrbitProgressSyncTests {
    private func sync(
        _ server: StubServer, fileID: Int, unstarted bookID: Int? = nil,
        started: @escaping @Sendable (LibraryReadStatus) -> Void = { _ in }
    ) -> BookOrbitProgressSync {
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: String(repeating: "a", count: 64)))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)
        return BookOrbitProgressSync(client: client, fileID: fileID, unstarted: bookID, started: started)
    }

    /// A server whose book 33 has `status` and file 34 `progress` (none:
    /// never opened); progress posts answer 201.
    private func server(status: String?, progress: String? = nil, failsStatus: Bool = false) -> StubServer {
        StubServer { request in
            switch (request.method, request.path) {
            case ("GET", "/api/v1/books/files/34/progress"):
                return .json(progress ?? #"{"cfi":null,"pageNumber":null,"percentage":0,"textUpdatedAt":null}"#)
            case ("GET", "/api/v1/books/33"):
                let status = status.map { #"{"status":"\#($0)","source":"manual"}"# } ?? "null"
                return .json(#"{"id":33,"title":"A Doll’s House","readStatus":\#(status)}"#)
            case ("PATCH", _): return failsStatus ? .json(500, "{}") : .json(#"{"status":"reading"}"#)
            default: return StubServer.Response(status: 201, headers: [:], body: Data())
            }
        }
    }

    @Test func pullsTheWebReadersPointCFIAsAFraction() async throws {
        let server = StubServer { _ in
            .json(#"{"cfi":"epubcfi(/6/14!/4/2/10/1:120)","pageNumber":null,"percentage":37.5,"textUpdatedAt":"2026-10-31T15:46:59.851Z"}"#)
        }

        let pulled = try #require(try await sync(server, fileID: 3).pull())

        #expect(server.requests.first?.path == "/api/v1/books/files/3/progress")
        #expect(pulled.position == ReadingPosition(cfi: "epubcfi(/6/14!/4/2/10/1:120)", fraction: 0.375))
        #expect(abs((pulled.updatedAt?.timeIntervalSince1970 ?? 0) - 1_793_461_619.851) < 0.001)
    }

    @Test func pullsNothingForANeverOpenedFile() async throws {
        let server = StubServer { _ in
            .json(#"{"cfi":null,"pageNumber":null,"percentage":0,"textUpdatedAt":null}"#)
        }
        #expect(try await sync(server, fileID: 1).pull() == nil)
    }

    @Test func pushesARangeCFIVerbatimWithAPercentage() async throws {
        let server = StubServer { _ in StubServer.Response(status: 201, headers: [:], body: Data()) }
        let range = "epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)"

        try await sync(server, fileID: 4).push(ReadingPosition(cfi: range, fraction: 0.0111))

        let body = try #require(server.requests.first?.json)
        #expect(server.requests.first?.path == "/api/v1/books/files/4/progress")
        #expect(body["cfi"] as? String == range)
        #expect(abs((body["percentage"] as? Double ?? 0) - 1.11) < 1e-9)
        #expect(Set(body.keys) == ["cfi", "percentage"])
    }

    // BookOrbit's own reader makes a Want to read book Reading once it's
    // started; its progress request alone doesn't (#120).
    @Test func startingAWantToReadBookMakesItReading() async throws {
        let server = server(status: "want_to_read")
        let told = Told()
        let sync = sync(server, fileID: 34, unstarted: 33) { told.append($0) }

        try await sync.push(ReadingPosition(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.02))
        try await sync.push(ReadingPosition(cfi: "epubcfi(/6/8!/4/4/1:0)", fraction: 0.03))

        #expect(server.requests.map { "\($0.method) \($0.path)" } == [
            "GET /api/v1/books/files/34/progress", "POST /api/v1/books/files/34/progress",
            "GET /api/v1/books/33", "PATCH /api/v1/books/33/status",
            "POST /api/v1/books/files/34/progress",
        ])
        #expect(server.requests[3].json as? [String: String] == ["status": "reading"])
        #expect(told.statuses == [.reading])
    }

    // The list's status may be old: one set since that starting leaves alone
    // stays.
    @Test func leavesAStatusThatStartingDoesntChange() async throws {
        let server = server(status: "abandoned")
        let told = Told()

        try await sync(server, fileID: 34, unstarted: 33) { told.append($0) }.push(ReadingPosition(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.02))

        #expect(server.requests.map(\.method) == ["GET", "POST", "GET"])
        #expect(told.statuses.isEmpty)
    }

    // BookOrbit's own reader leaves a hand-set status alone on a book that's
    // been started, here or elsewhere; the list's copy may not know.
    @Test func aBookTheServerHasAPlaceForKeepsItsStatus() async throws {
        let server = server(status: "want_to_read", progress: #"{"cfi":"epubcfi(/6/8!/4/2/1:0)","percentage":20,"textUpdatedAt":"2026-11-01T00:00:00.000Z"}"#)
        let sync = sync(server, fileID: 34, unstarted: 33)

        try await sync.push(ReadingPosition(cfi: "epubcfi(/6/8!/4/4/1:0)", fraction: 0.21))
        try await sync.push(ReadingPosition(cfi: "epubcfi(/6/8!/4/6/1:0)", fraction: 0.22))

        #expect(server.requests.map { "\($0.method) \($0.path)" } == [
            "GET /api/v1/books/files/34/progress", "POST /api/v1/books/files/34/progress", "POST /api/v1/books/files/34/progress",
        ])
    }

    @Test(arguments: [0, 1.0])
    func aPushThatDoesntStartTheBookLeavesItsStatus(fraction: Double) async throws {
        let server = server(status: "want_to_read")

        try await sync(server, fileID: 34, unstarted: 33).push(ReadingPosition(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: fraction))

        #expect(server.requests.map(\.method) == ["POST"])
    }

    @Test func triesAgainAfterAFailure() async throws {
        let server = server(status: "unread", failsStatus: true)
        let sync = sync(server, fileID: 34, unstarted: 33)

        try await sync.push(ReadingPosition(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.02))
        try await sync.push(ReadingPosition(cfi: "epubcfi(/6/8!/4/4/1:0)", fraction: 0.03))

        // The server's place is read once: after the first push it's this one.
        #expect(server.requests.map(\.method) == ["GET", "POST", "GET", "PATCH", "POST", "GET", "PATCH"])
    }

    @Test func aStartedBookPushesOnly() async throws {
        let server = server(status: "want_to_read")

        try await sync(server, fileID: 34).push(ReadingPosition(cfi: "epubcfi(/6/8!/4/2/1:0)", fraction: 0.02))

        #expect(server.requests.map(\.method) == ["POST"])
    }
}

private final class Told: Sendable {
    private let list = Mutex<[LibraryReadStatus]>([])
    var statuses: [LibraryReadStatus] { list.withLock { $0 } }
    func append(_ status: LibraryReadStatus) { list.withLock { $0.append(status) } }
}
