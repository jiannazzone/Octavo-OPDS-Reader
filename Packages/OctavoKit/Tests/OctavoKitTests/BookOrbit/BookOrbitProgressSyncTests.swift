import Foundation
import OctavoKit
import Testing

struct BookOrbitProgressSyncTests {
    private func sync(_ server: StubServer, fileID: Int) -> BookOrbitProgressSync {
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: String(repeating: "a", count: 64)))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)
        return BookOrbitProgressSync(client: client, fileID: fileID)
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
}
