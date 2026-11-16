import Foundation
import OctavoKit
import Testing

/// BookOrbit's highlights (`books/{bookId}/annotations`, #125), shapes
/// measured against v3.6.0.
struct BookOrbitHighlightSyncTests {
    private let cfi = "epubcfi(/6/4!/4/38/2,/1:143,/1:150)"

    func sync(_ server: StubServer) -> BookOrbitHighlightSync {
        let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: String(repeating: "a", count: 64)))
        let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)
        return BookOrbitHighlightSync(client: client, bookID: 4, fileID: 7)
    }

    private var annotation: String {
        ##"{"id":3,"bookId":4,"cfi":"epubcfi(/6/4!/4/38/2,/1:143,/1:150)","jumpFileId":4,"pageno":null,"text":"Collins","color":"#FACC15","style":"highlight","note":null,"chapterTitle":null,"origin":"web","pdf":null,"positionStatus":"exact","chapterIndex":null,"highlightedAt":"2026-11-16T00:38:10.794Z","createdAt":"2026-11-16T00:38:10.794Z","updatedAt":"2026-11-16T00:38:10.794Z","starredAt":null}"##
    }

    // Always for the file read, so the ranges are this file's.
    @Test func listsTheBooksHighlightsForTheFile() async throws {
        let server = StubServer { [annotation] _ in .json("[\(annotation)]") }
        let highlights = try await sync(server).highlights()
        let request = try #require(server.requests.first)
        #expect(request.path == "/api/v1/books/4/annotations")
        #expect(request.query == ["readerFileId": "7"])
        #expect(highlights.count == 1)
        #expect(highlights.first?.id == "3")
        #expect(highlights.first?.cfi == cfi)
        #expect(highlights.first?.text == "Collins")
        #expect(highlights.first?.color == "#FACC15")
        #expect(highlights.first?.updatedAt != nil)
    }

    @Test func oneThisFileDoesntHaveComesWithNoRange() async throws {
        let server = StubServer { _ in
            .json(#"[{"id":9,"cfi":null,"text":"It is a truth","color":"yellow","positionStatus":"failed","chapterTitle":"Chapter 1"}]"#)
        }
        let highlight = try #require(try await sync(server).highlights().first)
        #expect(highlight.cfi == nil)
        #expect(highlight.color == "yellow")
        #expect(highlight.chapter == "Chapter 1")
    }

    // The server rejects any field it doesn't know (400).
    @Test func addsWithOnlyTheFieldsTheServerTakes() async throws {
        let server = StubServer { [annotation] _ in .json(201, annotation) }
        let added = try await sync(server).add(NewHighlight(cfi: cfi, text: "Collins", color: "#4ADE80", chapter: String(repeating: "x", count: 600)))
        let request = try #require(server.requests.first)
        let body = try #require(request.json)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/books/4/annotations")
        #expect(Set(body.keys) == ["cfi", "bookFileId", "text", "color", "style", "chapterTitle"])
        #expect(body["bookFileId"] as? Int == 7)
        #expect(body["style"] as? String == "highlight")
        #expect((body["chapterTitle"] as? String)?.count == 500)
        #expect(added.id == "3")
    }

    @Test func anEditSendsOnlyWhatChanged() async throws {
        let server = StubServer { [annotation] _ in .json(annotation) }
        _ = try await sync(server).update(id: "3", HighlightEdit(color: "#38BDF8"))
        let request = try #require(server.requests.first)
        #expect(request.method == "PATCH")
        #expect(request.path == "/api/v1/books/4/annotations/3")
        #expect(Set(try #require(request.json).keys) == ["color"])
    }

    @Test func aClearedNoteIsSentAsNull() async throws {
        let server = StubServer { [annotation] _ in .json(annotation) }
        _ = try await sync(server).update(id: "3", HighlightEdit(note: .some(nil)))
        let body = try #require(server.requests.first?.json)
        #expect(Set(body.keys) == ["note"])
        #expect(body["note"] is NSNull)
    }

    @Test func editingOneDeletedElsewhereSaysItsGone() async {
        let server = StubServer { _ in .json(404, #"{"statusCode":404,"message":"Not Found"}"#) }
        await #expect(throws: HighlightSyncError.gone) { try await sync(server).update(id: "3", HighlightEdit(color: "#38BDF8")) }
    }

    @Test func removingOneThatsGoneSucceeds() async throws {
        let server = StubServer { _ in .json(404, #"{"statusCode":404,"message":"Not Found"}"#) }
        try await sync(server).remove(id: "3")
        #expect(server.requests.first?.method == "DELETE")
        #expect(server.requests.first?.path == "/api/v1/books/4/annotations/3")
    }

    @Test func otherFailuresStillThrow() async {
        let server = StubServer { _ in .json(500, #"{"statusCode":500,"message":"boom"}"#) }
        await #expect(throws: BookOrbitError.self) { try await sync(server).remove(id: "3") }
    }
}

extension BookOrbitHighlightSyncTests {
    @Test func aPDFsHighlightsAreLeftOut() async throws {
        let server = StubServer { _ in
            .json(#"[{"id":1,"cfi":null,"pdf":{"page":3,"rects":[]},"text":"In the PDF"},{"id":2,"cfi":"epubcfi(/6/4!/4/2,/1:0,/1:5)","pdf":null,"text":"In the EPUB"}]"#)
        }
        let highlights = try await sync(server).highlights()
        #expect(highlights.map(\.id) == ["2"])
    }
}
