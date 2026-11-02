import Foundation
import OctavoKit
import Testing

/// BookOrbit's bookmarks (`books/{bookId}/bookmarks`), shapes measured
/// against v3.6.0.
struct BookOrbitBookmarkSyncTests {
    private func sync(_ server: StubServer, bookID: Int = 3, fileID: Int? = 3) -> BookOrbitBookmarkSync {
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: String(repeating: "a", count: 64)))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)
        return BookOrbitBookmarkSync(client: client, bookID: bookID, fileID: fileID)
    }

    @Test func listsTheBooksBookmarks() async throws {
        let server = StubServer { _ in
            .json(#"[{"id":1,"bookId":3,"cfi":"epubcfi(/6/4!/4/44/1:54)","title":"Probe","positionSeconds":null,"createdAt":"2026-11-02T16:11:46.129Z","note":null,"updatedAt":"2026-11-02T16:11:46.129Z","clientId":"fb5bbd39","origin":"web","chapterId":null}]"#)
        }
        let bookmarks = try await sync(server).bookmarks()
        #expect(server.requests.first?.path == "/api/v1/books/3/bookmarks")
        #expect(bookmarks == [SyncedBookmark(id: "1", cfi: "epubcfi(/6/4!/4/44/1:54)", title: "Probe", createdAt: bookmarks.first?.createdAt)])
        #expect(bookmarks.first?.createdAt != nil)
    }

    // The server rejects any field it doesn't know (400).
    @Test func addsWithOnlyTheFieldsTheServerTakes() async throws {
        let server = StubServer { _ in
            .json(201, #"{"id":5,"bookId":3,"cfi":"epubcfi(/6/8!/4/2/1:0)","title":"CHAPTER 2. The Carpet-Bag."}"#)
        }
        let added = try await sync(server).add(cfi: "epubcfi(/6/8!/4/2/1:0)", title: String(repeating: "x", count: 600))
        let request = try #require(server.requests.first)
        let body = try #require(request.json)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/books/3/bookmarks")
        #expect(Set(body.keys) == ["cfi", "title", "bookFileId"])
        #expect((body["title"] as? String)?.count == 500)
        #expect(added.id == "5")
    }

    @Test func removingOneThatsGoneSucceeds() async throws {
        let server = StubServer { _ in .json(404, #"{"statusCode":404,"message":"Not Found"}"#) }
        try await sync(server).remove(id: "5")
        #expect(server.requests.first?.method == "DELETE")
        #expect(server.requests.first?.path == "/api/v1/books/3/bookmarks/5")
    }

    @Test func otherFailuresStillThrow() async {
        let server = StubServer { _ in .json(500, #"{"statusCode":500,"message":"boom"}"#) }
        await #expect(throws: BookOrbitError.self) { try await sync(server).remove(id: "5") }
    }
}
