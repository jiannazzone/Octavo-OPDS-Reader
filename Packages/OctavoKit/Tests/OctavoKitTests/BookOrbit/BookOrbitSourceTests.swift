import Foundation
@testable import OctavoKit
import Synchronization
import Testing

private func source(_ server: StubServer, pageSize: Int = 2, includesProgress: Bool = true) -> BookOrbitSource {
    let store = InMemoryBookOrbitTokenStore(BookOrbitCredentials(accessToken: "access-1", refreshToken: String(repeating: "a", count: 64)))
    let client = BookOrbitClient(baseURL: server.baseURL, tokenStore: store, configuration: server.configuration)
    return BookOrbitSource(client: client, pageSize: pageSize, includesProgress: includesProgress)
}

private func link(_ route: BookOrbitRoute) -> LibraryLink { route.link }

/// Trimmed `BookCard`s as BookOrbit v3.6.0 lists them.
private let alice = #"{"id":1,"libraryId":1,"title":"Alice's Adventures in Wonderland","seriesId":null,"seriesName":null,"seriesIndex":null,"authors":["Lewis Carroll"],"files":[{"id":1,"format":"epub","role":"primary","sizeBytes":189249}],"readingProgress":42.5,"hasCover":true,"coverVersion":"ebook:2026-10-31T15:45:45.480Z:-"}"#
private let frankenstein = #"{"id":2,"title":"Frankenstein","authors":["Mary Wollstonecraft Shelley"],"files":[{"id":2,"format":"epub","role":"primary"}],"hasCover":false}"#
private let study = #"{"id":7,"title":"A Study in Scarlet","seriesId":3,"seriesName":"Sherlock Holmes","seriesIndex":"1","authors":["Arthur Conan Doyle"],"files":[{"id":9,"format":"epub","role":"alternate"},{"id":8,"format":"epub","role":"primary"}],"hasCover":true}"#

private func page(_ items: String..., total: Int, page: Int = 0, size: Int = 2) -> StubServer.Response {
    .json(#"{"items":[\#(items.joined(separator: ","))],"total":\#(total),"page":\#(page),"size":\#(size)}"#)
}

struct BookOrbitRouteTests {
    @Test(arguments: [
        BookOrbitRoute.books(page: 0), .recent(page: 3), .books(page: 1, filter: .unread), .continueReading, .collections, .collection(id: 1, page: 2),
        .smartScope(id: 9, page: 0), .seriesList(page: 1), .series(id: 3, page: 0), .authors(page: 4), .author(id: 5, page: 1),
        .books(page: 2, sort: .author, filter: .finished), .recent(page: 0, filter: .reading), .collection(id: 1, page: 0, sort: .recentlyAdded),
        .smartScope(id: 9, page: 1, sort: .author, filter: .unread), .series(id: 3, page: 1, sort: .title, filter: .reading),
        .author(id: 5, page: 0, sort: .recentlyAdded, filter: .unread),
        .search(query: "pride", page: 0), .search(query: "Tom & Jerry = fun+ 100%?#/", page: 2), .search(query: "Brontë", page: 0),
    ])
    func roundTripsThroughLinks(route: BookOrbitRoute) {
        #expect(BookOrbitRoute(route.link) == route)
    }

    @Test func writesReadableLinks() {
        #expect(BookOrbitRoute.collection(id: 1, page: 2).link.rawValue == "collections/1?page=2")
        #expect(BookOrbitRoute.collections.link.rawValue == "collections")
        #expect(BookOrbitRoute.books(page: 0, sort: .author, filter: .unread).link.rawValue == "books?page=0&sort=author&show=unread")
        // A list's own sort isn't written, so each list has one link.
        #expect(BookOrbitRoute.books(page: 0, sort: .title).link.rawValue == "books?page=0")
        #expect(BookOrbitRoute.series(id: 3, page: 0, sort: .readingOrder).link.rawValue == "series/3?page=0")
    }

    @Test func aSortTheListDoesntOfferIsItsOwn() {
        #expect(BookOrbitRoute(LibraryLink(rawValue: "series/3?page=0&sort=author")) == .series(id: 3, page: 0))
        #expect(BookOrbitRoute(LibraryLink(rawValue: "books?page=0&sort=readingOrder&show=someday")) == .books(page: 0))
        #expect(BookOrbitRoute(LibraryLink(rawValue: "recent?page=0&sort=title")) == .recent(page: 0))
    }

    @Test(arguments: [
        "", "/books", "https://example.com/books", "//example.com/books", "books/1", "collections/abc", "collections/0", "collections/-1",
        "series/1/2", "search", "search?page=0", "books?page=-1", "opds/feed.xml", "smart-scopes",
    ])
    func rejectsForeignLinks(rawValue: String) {
        #expect(BookOrbitRoute(LibraryLink(rawValue: rawValue)) == nil)
    }
}

struct BookOrbitSourceTests {
    @Test func rootHasTheFourChipsAndFullSearch() async throws {
        let server = StubServer { _ in .json("[]") }
        let root = try await source(server).root()

        #expect(root.chips.map(\.title) == ["All", "Collections", "Series", "Authors"])
        #expect(root.chips.map(\.link) == [link(.books(page: 0)), link(.collections), link(.seriesList(page: 0)), link(.authors(page: 0))])
        #expect(root.search == .booksSeriesAndAuthors)
        #expect(root.recentlyAdded == link(.recent(page: 0)))
        #expect(root.unread == link(.books(page: 0, filter: .unread)))
        #expect(root.continueReading == link(.continueReading))
        #expect(server.requests.isEmpty)
    }

    @Test func allBooksQueriesByTitleAndPages() async throws {
        let server = StubServer { request in
            let page = (request.json?["pagination"] as? [String: Any])?["page"] as? Int
            return page == 0 ? .json(201, #"{"items":[\#(alice),\#(frankenstein)],"total":3,"page":0,"size":2}"#)
                             : .json(201, #"{"items":[\#(study)],"total":3,"page":1,"size":2}"#)
        }
        let source = source(server)

        let first = try await source.feed(link(.books(page: 0)))
        #expect(first.title == "All")
        #expect(first.books.map(\.title) == ["Alice's Adventures in Wonderland", "Frankenstein"])
        #expect(first.total == 3)
        #expect(first.next == link(.books(page: 1)))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/books/query")
        let body = try #require(request.json)
        #expect(Set(body.keys) == ["sort", "pagination"])
        #expect(body["sort"] as? [[String: String]] == [["field": "title", "dir": "asc"]])
        #expect(body["pagination"] as? [String: Int] == ["page": 0, "size": 2])

        let second = try await source.feed(try #require(first.next))
        #expect(second.books.map(\.title) == ["A Study in Scarlet"])
        #expect(second.next == nil)
    }

    @Test func recentlyAddedSortsNewestFirst() async throws {
        let server = StubServer { _ in .json(201, #"{"items":[\#(alice)],"total":1,"page":0,"size":2}"#) }
        _ = try await source(server).feed(link(.recent(page: 0)))
        #expect(server.requests.first?.json?["sort"] as? [[String: String]] == [["field": "addedAt", "dir": "desc"]])
    }

    @Test func unreadFiltersOnStatusAndProgressByTitle() async throws {
        let server = StubServer { request in
            let page = (request.json?["pagination"] as? [String: Any])?["page"] as? Int
            return page == 0 ? .json(201, #"{"items":[\#(frankenstein),\#(study)],"total":3,"page":0,"size":2}"#)
                             : .json(201, #"{"items":[\#(alice)],"total":3,"page":1,"size":2}"#)
        }
        let source = source(server)

        let first = try await source.feed(link(.books(page: 0, filter: .unread)))
        #expect(first.books.map(\.title) == ["Frankenstein", "A Study in Scarlet"])
        #expect(first.total == 3)
        #expect(first.next == link(.books(page: 1, filter: .unread)))
        let body = try #require(server.requests.first?.json)
        #expect(Set(body.keys) == ["filter", "sort", "pagination"])
        #expect(body["sort"] as? [[String: String]] == [["field": "title", "dir": "asc"]])
        // Measured against v3.6.0 (`docs/notes/bookorbit-api.md`, "Filtering").
        let filter = try JSONSerialization.data(withJSONObject: try #require(body["filter"]), options: .sortedKeys)
        #expect(String(decoding: filter, as: UTF8.self) == #"{"join":"AND","rules":[{"field":"readProgress","operator":"isUnread","type":"rule"},{"join":"OR","rules":[{"field":"readStatus","operator":"isEmpty","type":"rule"},{"field":"readStatus","operator":"includesAny","type":"rule","value":["unread","want_to_read"]}],"type":"group"}],"type":"group"}"#)

        let second = try await source.feed(try #require(first.next))
        #expect(second.books.map(\.title) == ["Alice's Adventures in Wonderland"])
        #expect(second.next == nil)
    }

    @Test func continueReadingIsBookOrbitsOwnList() async throws {
        let reading = #"{"id":4,"title":"Pride and Prejudice","authors":["Jane Austen"],"files":[{"id":4,"format":"epub","role":"primary"}],"readingProgress":2.5,"readStatus":{"status":"reading","source":"auto","startedAt":"2026-10-31T00:00:00.000Z","finishedAt":null,"updatedAt":"2026-11-01T14:08:50.887Z"}}"#
        let server = StubServer { _ in .json(#"{"books":[\#(reading),\#(frankenstein)],"total":2}"#) }

        let feed = try await source(server).feed(link(.continueReading))

        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/api/v1/dashboard/scrollers/continue-reading")
        #expect(request.query == ["limit": "20"])
        #expect(feed.books.map(\.title) == ["Pride and Prejudice", "Frankenstein"])
        #expect(feed.books[0].progress == 0.025)
        #expect(feed.books[0].lastReadAt == Date(timeIntervalSinceReferenceDate: 815_234_930.887))
        #expect(feed.books[1].lastReadAt == nil)
        #expect(feed.books[0].isFinished == false)
        #expect(feed.books[1].isFinished == nil)
        #expect(feed.books[0].readStatus == .reading)
        #expect(feed.books[1].readStatus == nil)
        #expect(feed.next == nil)
    }

    // Setup's "Don't sync": the iPhone keeps its own place, so no list
    // shows the server's.
    @Test func leavesOutTheServersProgressWhenAsked() async throws {
        let reading = #"{"id":4,"title":"Pride and Prejudice","authors":["Jane Austen"],"files":[{"id":4,"format":"epub","role":"primary"}],"readingProgress":2.5,"readStatus":{"status":"reading","source":"auto","startedAt":"2026-10-31T00:00:00.000Z","finishedAt":null,"updatedAt":"2026-11-01T14:08:50.887Z"}}"#
        let server = StubServer { _ in .json(#"{"books":[\#(reading)],"total":1}"#) }

        let feed = try await source(server, includesProgress: false).feed(link(.continueReading))

        #expect(feed.books[0].progress == nil)
        #expect(feed.books[0].isFinished == false)
        #expect(feed.books[0].lastReadAt != nil)
    }

    // Measured on v3.6.0: `read` sets finishedAt; `reading` afterwards is
    // stored as `rereading`.
    @Test func marksFinishedAsBookOrbitsReadStatus() async throws {
        let server = StubServer { _ in .json(#"{"status":"read"}"#) }
        let source = source(server)
        #expect(source.tracksFinished)
        let book = LibraryBook(id: LibraryBookID(rawValue: "4"), title: "Pride and Prejudice")

        try await source.setFinished(true, for: book)
        try await source.setFinished(false, for: book)

        #expect(server.requests.map(\.method) == ["PATCH", "PATCH"])
        #expect(server.requests.map(\.path) == ["/api/v1/books/4/status", "/api/v1/books/4/status"])
        // The server rejects fields it doesn't know, so only the status goes.
        #expect(server.requests.map { $0.json as? [String: String] } == [["status": "read"], ["status": "reading"]])
    }

    // Measured on v3.6.0 (`docs/notes/book-status.md`): each value is
    // BookOrbit's own, and the body takes nothing else.
    @Test(arguments: LibraryReadStatus.allCases)
    func setsEachReadStatus(status: LibraryReadStatus) async throws {
        let server = StubServer { _ in .json(#"{"status":"\#(status.rawValue)"}"#) }
        let source = source(server)
        #expect(source.tracksReadStatus)

        try await source.setReadStatus(status, for: LibraryBook(id: LibraryBookID(rawValue: "33"), title: "A Doll’s House"))

        #expect(server.requests.map(\.method) == ["PATCH"])
        #expect(server.requests.map(\.path) == ["/api/v1/books/33/status"])
        #expect(server.requests.first?.json as? [String: String] == ["status": status.rawValue])
    }

    @Test func mapsBooksForTheGrid() async throws {
        let server = StubServer { _ in .json(201, #"{"items":[\#(alice),\#(frankenstein),\#(study)],"total":3}"#) }
        let books = try await source(server, pageSize: 3).feed(link(.books(page: 0))).books

        let alice = books[0]
        #expect(alice.id == LibraryBookID(rawValue: "1"))
        #expect(alice.authors == ["Lewis Carroll"])
        #expect(alice.progress == 0.425)
        #expect(alice.cover == LibraryCover(rawValue: "books/1", version: "ebook:2026-10-31T15:45:45.480Z:-"))
        #expect(alice.files == [LibraryFile(id: LibraryFileID(rawValue: "1"), format: "epub", sizeBytes: 189_249, isPrimary: true)])
        #expect(alice.series == nil)

        #expect(books[1].cover == nil)
        #expect(books[1].progress == nil)

        let study = books[2]
        #expect(study.series == LibrarySeriesPosition(name: "Sherlock Holmes", position: 1, link: link(.series(id: 3, page: 0))))
        #expect(study.primaryFile?.id == LibraryFileID(rawValue: "8"))
        #expect(BookOrbitSource.fileID(of: try #require(study.primaryFile)) == 8)
    }

    @Test func collectionsListBothKindsWithoutPodcasts() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/collections":
                .json(#"""
                [{"id":1,"mediaType":"books","name":"Classics","icon":"Rocket","description":"Old ones","bookCount":5},
                 {"id":2,"mediaType":"podcasts","name":"Shows","bookCount":0},
                 {"id":3,"name":"No media type","bookCount":1}]
                """#)
            default:
                .json(#"""
                [{"id":4,"mediaType":"books","name":"Unread","bookCount":12,"filter":{"type":"group","join":"AND","rules":[]}},
                 {"id":5,"mediaType":"podcasts","name":"New episodes"}]
                """#)
            }
        }

        let feed = try await source(server).feed(link(.collections))

        #expect(feed.title == "Collections")
        #expect(feed.books.isEmpty)
        #expect(feed.entries == [
            LibraryEntry(kind: .collection, title: "Classics", subtitle: "Old ones", count: 5, link: link(.collection(id: 1, page: 0))),
            LibraryEntry(kind: .collection, title: "No media type", count: 1, link: link(.collection(id: 3, page: 0))),
            LibraryEntry(kind: .smartCollection, title: "Unread", count: 12, link: link(.smartScope(id: 4, page: 0))),
        ])
        #expect(feed.next == nil)
        #expect(Set(server.requests.map(\.path)) == ["/api/v1/collections", "/api/v1/smart-scopes"])
        #expect(server.requests.allSatisfy { $0.query.isEmpty })
    }

    @Test(arguments: [
        (BookOrbitRoute.series(id: 3, page: 0), "/api/v1/series/3/books", ["page": "0", "size": "2", "sort": "seriesIndex", "order": "asc"]),
        (.series(id: 3, page: 1, sort: .recentlyAdded), "/api/v1/series/3/books", ["page": "1", "size": "2", "sort": "addedAt", "order": "desc"]),
        (.author(id: 5, page: 2), "/api/v1/authors/5/books", ["page": "2", "size": "2", "sort": "title", "order": "asc"]),
        (.author(id: 5, page: 0, sort: .recentlyAdded), "/api/v1/authors/5/books", ["page": "0", "size": "2", "sort": "addedAt", "order": "desc"]),
    ])
    func opensListsOfBooks(route: BookOrbitRoute, path: String, query: [String: String]) async throws {
        let server = StubServer { _ in page(alice, frankenstein, total: 9) }

        let feed = try await source(server).feed(route.link)

        #expect(feed.books.count == 2)
        #expect(feed.total == 9)
        #expect(feed.next != nil)
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == path)
        #expect(request.query == query)
    }

    @Test(arguments: [
        (BookOrbitRoute.books(page: 1, sort: .author, filter: .reading), BookOrbitRoute.books(page: 2, sort: .author, filter: .reading),
         "/api/v1/books/query", ["field": "author", "dir": "asc"]),
        (.collection(id: 1, page: 1), .collection(id: 1, page: 2), "/api/v1/collections/1/books/query", ["field": "title", "dir": "asc"]),
        (.smartScope(id: 4, page: 1, sort: .recentlyAdded, filter: .reading), .smartScope(id: 4, page: 2, sort: .recentlyAdded, filter: .reading),
         "/api/v1/smart-scopes/4/books/query", ["field": "addedAt", "dir": "desc"]),
    ])
    func queriesListsOfBooksOnTheServer(route: BookOrbitRoute, next: BookOrbitRoute, path: String, sort: [String: String]) async throws {
        let server = StubServer { _ in page(alice, frankenstein, total: 9, page: 1) }

        let feed = try await source(server).feed(route.link)

        #expect(feed.books.count == 2)
        #expect(feed.total == 9)
        #expect(feed.next == next.link)
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == path)
        #expect(request.query.isEmpty)
        let body = try #require(request.json)
        #expect(body["sort"] as? [[String: String]] == [sort])
        #expect(body["pagination"] as? [String: Int] == ["page": 1, "size": 2])
        #expect((body["filter"] != nil) == (route.order?.filter != .all))
    }

    @Test(arguments: [
        // Measured against v3.6.0 (`docs/notes/book-status.md`).
        (LibraryFilter.reading, #"{"join":"OR","rules":[{"field":"readStatus","operator":"includesAny","type":"rule","value":["reading","rereading"]},{"join":"AND","rules":[{"field":"readStatus","operator":"includesAny","type":"rule","value":["on_hold","want_to_read"]},{"field":"readProgress","operator":"isInProgress","type":"rule"}],"type":"group"}],"type":"group"}"#),
        (.finished, #"{"join":"AND","rules":[{"field":"readStatus","operator":"includesAny","type":"rule","value":["read"]}],"type":"group"}"#),
    ])
    func filtersOnTheServersStatus(filter: LibraryFilter, json: String) async throws {
        let server = StubServer { _ in page(alice, total: 1) }

        _ = try await source(server).feed(link(.books(page: 0, filter: filter)))

        let body = try #require(server.requests.first?.json)
        let sent = try JSONSerialization.data(withJSONObject: try #require(body["filter"]), options: .sortedKeys)
        #expect(String(decoding: sent, as: UTF8.self) == json)
    }

    @Test func offersSortsAndFiltersOnListsOfBooks() {
        let source = source(StubServer { _ in .json("[]") })
        let all = LibraryFilter.allCases

        #expect(source.order(of: link(.books(page: 0))) == LibraryListOrder(
            sorts: [.title, .author, .recentlyAdded], filters: all, sort: .title, filter: .all, takesRememberedSort: true
        ))
        #expect(source.order(of: link(.collection(id: 1, page: 0, sort: .author, filter: .unread)))?.sort == .author)
        #expect(source.order(of: link(.collection(id: 1, page: 0, sort: .author, filter: .unread)))?.filter == .unread)
        #expect(source.order(of: link(.series(id: 3, page: 0))) == LibraryListOrder(
            sorts: [.readingOrder, .title, .recentlyAdded], filters: all, sort: .readingOrder, filter: .all, takesRememberedSort: false
        ))
        #expect(source.order(of: link(.author(id: 5, page: 0)))?.sorts == [.title, .recentlyAdded])
        #expect(source.order(of: link(.recent(page: 0))) == LibraryListOrder(
            sorts: [], filters: all, sort: nil, filter: .all, takesRememberedSort: false
        ))
        for route in [BookOrbitRoute.collections, .seriesList(page: 0), .authors(page: 0), .continueReading, .search(query: "pride", page: 0)] {
            #expect(source.order(of: route.link) == nil)
        }
    }

    @Test func linksEachSortAndFilterFromTheTop() {
        let source = source(StubServer { _ in .json("[]") })

        #expect(source.link(link(.books(page: 3)), sortedBy: .author, showing: .unread) == link(.books(page: 0, sort: .author, filter: .unread)))
        #expect(source.link(link(.books(page: 0, filter: .unread)), sortedBy: .title, showing: .all) == link(.books(page: 0)))
        // A sort the list doesn't offer gives its own.
        #expect(source.link(link(.series(id: 3, page: 0)), sortedBy: .author, showing: .finished) == link(.series(id: 3, page: 0, filter: .finished)))
        #expect(source.link(link(.recent(page: 0)), sortedBy: .title, showing: .reading) == link(.recent(page: 0, filter: .reading)))
        #expect(source.link(link(.authors(page: 0)), sortedBy: .title, showing: .unread) == link(.authors(page: 0)))
    }

    /// `books/query` matches an author by any part of the name, so a
    /// series' or an author's books filter here, from every page of the
    /// list itself.
    @Test(arguments: [
        (BookOrbitRoute.series(id: 3, page: 0, sort: .title, filter: .unread), "/api/v1/series/3/books", "title"),
        (.author(id: 5, page: 0, filter: .unread), "/api/v1/authors/5/books", "title"),
    ])
    func filtersASeriesOrAnAuthorOnTheIPhone(route: BookOrbitRoute, path: String, sort: String) async throws {
        @Sendable func book(_ id: Int, status: String?, progress: Double?) -> String {
            let status = status.map { #"{"status":"\#($0)"}"# } ?? "null"
            let progress = progress.map { String($0) } ?? "null"
            return #"{"id":\#(id),"title":"Book \#(id)","readStatus":\#(status),"readingProgress":\#(progress)}"#
        }
        let server = StubServer { request in
            let page = Int(request.query["page"] ?? "") ?? -1
            // A full page of 100, then a short one.
            let books = page == 0
                ? (1...100).map { book($0, status: $0 == 1 ? "reading" : nil, progress: $0 == 2 ? 10 : nil) }
                : [book(101, status: "unread", progress: 0), book(102, status: "read", progress: nil), book(103, status: "want_to_read", progress: nil)]
            return .json(#"{"items":[\#(books.joined(separator: ","))],"total":103,"page":\#(page),"size":100}"#)
        }

        let feed = try await source(server).feed(route.link)

        #expect(feed.books.map(\.id.rawValue) == (3...101).map(String.init) + ["103"])
        #expect(feed.total == 100)
        #expect(feed.next == nil)
        #expect(feed.loadedOnly == nil)
        #expect(server.requests.map(\.path) == [path, path])
        #expect(server.requests.map { $0.query["page"] } == ["0", "1"])
        #expect(server.requests.allSatisfy { $0.query["size"] == "100" && $0.query["sort"] == sort })
    }

    @Test func aFilteredListSaysWhereItStopped() async throws {
        let server = StubServer { request in
            let page = Int(request.query["page"] ?? "") ?? 0
            let books = (1...100).map { #"{"id":\#(page * 100 + $0),"title":"Book"}"# }
            return .json(#"{"items":[\#(books.joined(separator: ","))],"total":2500,"page":\#(page),"size":100}"#)
        }

        let feed = try await source(server).feed(link(.author(id: 5, page: 0, filter: .unread)))

        #expect(feed.books.count == 2_000)
        #expect(feed.loadedOnly == 2_000)
        #expect(server.requests.count == 20)
    }

    @Test(arguments: [
        // (status, progress as BookOrbit sends it, unread, reading, finished)
        ("null", "null", true, false, false),
        (#"{"status":"unread"}"#, "0", true, false, false),
        (#"{"status":"unread"}"#, "30", false, false, false),
        (#"{"status":"reading"}"#, "0", false, true, false),
        (#"{"status":"rereading"}"#, "50", false, true, false),
        (#"{"status":"read"}"#, "100", false, false, true),
        (#"{"status":"want_to_read"}"#, "null", true, false, false),
        (#"{"status":"want_to_read"}"#, "30", false, true, false),
        (#"{"status":"want_to_read"}"#, "100", false, false, false),
        (#"{"status":"on_hold"}"#, "30", false, true, false),
        (#"{"status":"on_hold"}"#, "null", false, false, false),
        (#"{"status":"skimmed"}"#, "30", false, false, false),
        (#"{"status":"abandoned"}"#, "30", false, false, false),
        (#"{"status":"read"}"#, "40", false, false, true),
        // One a newer BookOrbit added: only under All books, as on the server.
        (#"{"status":"shelved"}"#, "null", false, false, false),
    ])
    func matchesBooksAsTheServerDoes(status: String, progress: String, unread: Bool, reading: Bool, finished: Bool) throws {
        let json = #"{"id":1,"title":"Book","readStatus":\#(status),"readingProgress":\#(progress)}"#
        let book = try JSONDecoder().decode(BookOrbitBook.self, from: Data(json.utf8))
        #expect(LibraryFilter.all.matches(book))
        #expect(LibraryFilter.unread.matches(book) == unread)
        #expect(LibraryFilter.reading.matches(book) == reading)
        #expect(LibraryFilter.finished.matches(book) == finished)
    }

    @Test func seriesListByNameWithCovers() async throws {
        let server = StubServer { _ in
            .json(#"""
            {"items":[{"id":3,"name":"Sherlock Holmes","bookCount":4,"readCount":1,"authors":["Arthur Conan Doyle"],
              "coverBookIds":[7,8,9,10],"volumes":[],"gaps":[]},
             {"id":4,"name":"Discworld","bookCount":2,"authors":[],"coverBookIds":null}],
             "total":2,"page":0,"size":2,"facets":{"all":2}}
            """#)
        }

        let feed = try await source(server).feed(link(.seriesList(page: 0)))

        #expect(server.requests.first?.query == ["page": "0", "size": "2", "sort": "name", "order": "asc"])
        #expect(feed.entries.first == LibraryEntry(
            kind: .series, title: "Sherlock Holmes", subtitle: "Arthur Conan Doyle", count: 4,
            previewCovers: [7, 8, 9].map { LibraryCover(rawValue: "books/\($0)") }, link: link(.series(id: 3, page: 0))
        ))
        #expect(feed.entries.last?.subtitle == nil)
        #expect(feed.entries.last?.previewCovers == [])
        #expect(feed.next == nil)
    }

    @Test func seriesBooksKeepTheirNumbers() async throws {
        let server = StubServer { _ in
            .json(#"""
            {"items":[{"id":7,"title":"A Study in Scarlet","seriesId":3,"seriesName":"Sherlock Holmes","seriesIndex":"1"},
                      {"id":8,"title":"The Sign of the Four","seriesId":3,"seriesName":"Sherlock Holmes","seriesIndex":"2.5"},
                      {"id":9,"title":"Old server","seriesId":3,"seriesName":"Sherlock Holmes","seriesIndex":3}],
             "total":3,"page":0,"size":3,"seriesInfo":{"id":3,"name":"Sherlock Holmes"}}
            """#)
        }
        let feed = try await source(server, pageSize: 3).feed(link(.series(id: 3, page: 0)))
        #expect(feed.books.map(\.series?.position) == [1, 2.5, 3])
    }

    @Test func authorsBySortName() async throws {
        let server = StubServer { _ in
            .json(#"""
            {"items":[{"id":4,"name":"Jane Austen","sortName":"Austen, Jane","bookCount":1,"coverBookId":4,"imageUrl":null},
                      {"id":1,"name":"Lewis Carroll","sortName":null,"bookCount":1,"coverBookId":null,
                       "imageUrl":"/api/v1/authors/1/thumbnail?t=1730390400"}],
             "total":5,"page":0,"size":2}
            """#)
        }

        let feed = try await source(server).feed(link(.authors(page: 0)))

        #expect(server.requests.first?.query == ["page": "0", "size": "2", "sort": "sortName", "order": "asc"])
        #expect(feed.entries.first == LibraryEntry(
            kind: .author, title: "Jane Austen", count: 1, sortName: "Austen, Jane",
            previewCovers: [LibraryCover(rawValue: "books/4")], link: link(.author(id: 4, page: 0))
        ))
        #expect(feed.entries.last?.previewCovers == [])
        #expect(feed.entries.last?.portrait == LibraryCover(rawValue: "authors/1", version: "1730390400"))
        #expect(feed.next == link(.authors(page: 1)))
    }

    @Test func pagesWithoutTotalUntilShortPage() async throws {
        let server = StubServer { request in
            request.query["page"] == "0" ? .json(#"{"items":[\#(alice),\#(frankenstein)]}"#) : .json(#"{"items":[\#(study)]}"#)
        }
        let source = source(server)
        let first = try await source.feed(link(.author(id: 1, page: 0)))
        #expect(first.next == link(.author(id: 1, page: 1)))
        #expect(try await source.feed(link(.author(id: 1, page: 1))).next == nil)
    }

    @Test func dropsBooksThatDoNotDecode() async throws {
        let server = StubServer { _ in .json(#"{"items":[\#(alice),{"title":"no id"},"junk",null,{"id":5,"title":null}],"total":5}"#) }
        let books = try await source(server, pageSize: 5).feed(link(.collection(id: 1, page: 0))).books
        #expect(books.map(\.id.rawValue) == ["1", "5"])
        #expect(books.last?.title == "")
    }

    // MARK: Search

    @Test func searchesBooksSeriesAndAuthors() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/books/query":
                return .json(201, #"{"items":[\#(study),\#(alice)],"total":3,"page":0,"size":2}"#)
            default:
                return .json(#"""
                {"query":"holmes",
                 "books":{"items":[{"item":\#(study),"matchedField":"series","matchedText":"Sherlock Holmes"}],"total":1},
                 "authors":{"items":[{"item":{"id":5,"name":"Arthur Conan Doyle","sortName":"Doyle, Arthur Conan","bookCount":4},"matchedField":"name"}],"total":1},
                 "series":{"items":[{"item":{"id":3,"name":"Sherlock Holmes","bookCount":4,"authors":["Arthur Conan Doyle"],"coverBookIds":[7]},"matchedField":"name"}],"total":1}}
                """#)
            }
        }

        let results = try await source(server).search("  holmes ")

        #expect(results.query == "holmes")
        #expect(results.books.books.map(\.title) == ["A Study in Scarlet", "Alice's Adventures in Wonderland"])
        #expect(results.books.next == link(.search(query: "holmes", page: 1)))
        #expect(results.booksLink == link(.search(query: "holmes", page: 0)))
        #expect(results.series.map(\.title) == ["Sherlock Holmes"])
        #expect(results.series.first?.link == link(.series(id: 3, page: 0)))
        #expect(results.authors.map(\.title) == ["Arthur Conan Doyle"])
        #expect(results.authors.first?.link == link(.author(id: 5, page: 0)))

        let query = try #require(server.requests(to: "/api/v1/books/query").first?.json)
        #expect(query["q"] as? String == "holmes")
        #expect(query["sort"] as? [[String: String]] == [["field": "relevance", "dir": "desc"]])
        #expect(server.requests(to: "/api/v1/search").first?.query == ["q": "holmes", "limit": "10"])
    }

    @Test func searchFeedPagesOnWithTheQuery() async throws {
        let server = StubServer { _ in .json(201, #"{"items":[\#(alice)],"total":3,"page":1,"size":2}"#) }
        let feed = try await source(server).feed(link(.search(query: "the", page: 1)))
        #expect(feed.books.count == 1)
        #expect(feed.next == nil)
        let body = try #require(server.requests.first?.json)
        #expect(body["q"] as? String == "the")
        #expect(body["pagination"] as? [String: Int] == ["page": 1, "size": 2])
    }

    @Test(arguments: ["", " ", "a", " a "])
    func skipsQueriesBookOrbitWouldReject(query: String) async throws {
        let server = StubServer { _ in .json(400, #"{"statusCode":400,"message":["q must be longer than or equal to 2 characters"]}"#) }
        let results = try await source(server).search(query)
        #expect(results.books.books.isEmpty)
        #expect(results.series.isEmpty && results.authors.isEmpty)
        #expect(server.requests.isEmpty)
    }

    // MARK: Details, covers, download

    @Test func detailsLinkAuthorsSeriesAndCollections() async throws {
        let server = StubServer { _ in
            .json(#"""
            {"id":7,"title":"A Study in Scarlet","subtitle":null,"description":"<p>Holmes meets Watson.</p>","publisher":"Ward Lock",
             "language":"en","publishedDate":null,"publishedYear":1887,"addedAt":"2026-10-31T15:45:45.873Z",
             "seriesId":3,"seriesName":"Sherlock Holmes","seriesIndex":"1",
             "seriesMemberships":[{"seriesId":3,"seriesName":"Sherlock Holmes","seriesIndex":"1","displayOrder":0},
                                  {"seriesId":6,"seriesName":"Victorian Detectives","seriesIndex":null,"displayOrder":1}],
             "authors":[{"id":5,"name":"Arthur Conan Doyle","sortName":"Doyle, Arthur Conan"}],
             "collections":[{"id":1,"name":"Classics"}],
             "files":[{"id":8,"format":"epub","role":"primary","sizeBytes":1000,"filename":"A Study in Scarlet.epub"}],
             "readingProgress":null,"hasCover":true,"coverVersion":"v2"}
            """#)
        }
        let listed = LibraryBook(id: LibraryBookID(rawValue: "7"), title: "A Study in Scarlet", progress: 0.3)

        let details = try await source(server).details(for: listed)

        #expect(server.requests.first?.path == "/api/v1/books/7")
        #expect(details.book.progress == 0.3)
        #expect(details.book.cover?.version == "v2")
        #expect(details.book.primaryFile?.filename == "A Study in Scarlet.epub")
        #expect(details.description == "<p>Holmes meets Watson.</p>")
        #expect(details.publisher == "Ward Lock")
        #expect(details.published == "1887")
        #expect(details.addedAt != nil)
        #expect(details.authors == [
            LibraryEntry(kind: .author, title: "Arthur Conan Doyle", sortName: "Doyle, Arthur Conan", link: link(.author(id: 5, page: 0))),
        ])
        #expect(details.series == [
            LibrarySeriesPosition(name: "Sherlock Holmes", position: 1, link: link(.series(id: 3, page: 0))),
            LibrarySeriesPosition(name: "Victorian Detectives", link: link(.series(id: 6, page: 0))),
        ])
        #expect(details.collections == [LibraryEntry(kind: .collection, title: "Classics", link: link(.collection(id: 1, page: 0)))])
    }

    @Test func authorWithoutIDLinksToSearch() async throws {
        let server = StubServer { _ in .json(#"{"id":2,"title":"Frankenstein","authors":["Mary Shelley"]}"#) }
        let details = try await source(server).details(for: LibraryBook(id: LibraryBookID(rawValue: "2"), title: "Frankenstein"))
        #expect(details.authors.first?.link == link(.search(query: "Mary Shelley", page: 0)))
        #expect(details.series.isEmpty)
    }

    @Test func fetchesThumbnailOrFullCover() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let server = StubServer { _ in StubServer.Response(status: 200, headers: ["Content-Type": "image/jpeg"], body: jpeg) }
        let source = source(server)
        let cover = LibraryCover(rawValue: "books/4", version: "v1")

        #expect(try await source.cover(cover, size: .thumbnail) == jpeg)
        #expect(try await source.cover(cover, size: .full) == jpeg)
        #expect(server.requests.map(\.path) == ["/api/v1/books/4/thumbnail", "/api/v1/books/4/cover"])
        #expect(try await source.cover(LibraryCover(rawValue: "authors/1", version: "7"), size: .thumbnail) == jpeg)
        #expect(server.requests.last?.path == "/api/v1/authors/1/thumbnail")
        #expect(server.requests.first?.headers["accept"] == "image/*")
        #expect(server.requests.first?.headers["authorization"] == "Bearer access-1")
        #expect(cover.cacheKey == "books/4@v1")
    }

    @Test func downloadsWithProgress() async throws {
        let epub = Data(repeating: 0x50, count: 300_000)
        let server = StubServer { _ in
            StubServer.Response(status: 200, headers: ["Content-Type": "application/epub+zip", "Content-Length": String(epub.count)], body: epub)
        }
        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-tests-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: destination) }
        let reported = Mutex<[Double]>([])
        let file = LibraryFile(id: LibraryFileID(rawValue: "4"), format: "epub", isPrimary: true)

        try await source(server).download(file, to: destination) { value in reported.withLock { $0.append(value) } }

        #expect(server.requests.first?.path == "/api/v1/books/files/4/serve")
        #expect(try Data(contentsOf: destination) == epub)
        let values = reported.withLock { $0 }
        #expect(values.last == 1)
        #expect(values == values.sorted())
    }

    @Test func progressIgnoresTheUnauthorizedAttempt() async throws {
        let epub = Data(repeating: 0x50, count: 100_000)
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/auth/refresh":
                return .json(#"{"accessToken":"access-2","refreshToken":"\#(String(repeating: "b", count: 64))"}"#)
            default:
                guard request.headers["authorization"] == "Bearer access-2" else { return .unauthorized }
                return StubServer.Response(status: 200, headers: ["Content-Length": String(epub.count)], body: epub)
            }
        }
        let destination = FileManager.default.temporaryDirectory.appending(path: "octavo-tests-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: destination) }
        let reported = Mutex<[Double]>([])

        try await source(server).download(LibraryFile(id: LibraryFileID(rawValue: "4")), to: destination) { value in
            reported.withLock { $0.append(value) }
        }

        #expect(try Data(contentsOf: destination) == epub)
        let values = reported.withLock { $0 }
        #expect(values.last == 1)
        #expect(values == values.sorted())
    }

    // MARK: Errors

    @Test func mapsBookOrbitErrors() async throws {
        let server = StubServer { request in
            switch request.path {
            case "/api/v1/books/1": .json(404, #"{"statusCode":404,"message":"Book not found"}"#)
            case "/api/v1/books/2": .json(500, #"{"statusCode":500,"message":"Boom"}"#)
            case "/api/v1/books/3": .json("not json")
            default: .unauthorized
            }
        }
        let source = source(server)
        func details(_ id: String) async throws { _ = try await source.details(for: LibraryBook(id: LibraryBookID(rawValue: id), title: "")) }

        await #expect(throws: LibraryError.notFound) { try await details("1") }
        await #expect(throws: LibraryError.server(status: 500, message: "Boom")) { try await details("2") }
        await #expect(throws: LibraryError.invalidResponse) { try await details("3") }
        await #expect(throws: LibraryError.signedOut) { try await details("4") }
    }

    @Test func signedOutWithoutCredentials() async {
        let server = StubServer { _ in .json("[]") }
        let source = BookOrbitSource(client: BookOrbitClient(baseURL: server.baseURL, configuration: server.configuration))
        await #expect(throws: LibraryError.signedOut) { try await source.feed(link(.collections)) }
    }

    @Test func rejectsLinksFromElsewhere() async {
        let server = StubServer { _ in .json("[]") }
        let source = source(server)
        await #expect(throws: LibraryError.invalidLink) { try await source.feed(LibraryLink(rawValue: "https://calibre.example/opds")) }
        await #expect(throws: LibraryError.invalidLink) { try await source.cover(LibraryCover(rawValue: "https://calibre.example/cover.jpg"), size: .full) }
        await #expect(throws: LibraryError.invalidLink) {
            try await source.details(for: LibraryBook(id: LibraryBookID(rawValue: "urn:uuid:1"), title: ""))
        }
        await #expect(throws: LibraryError.invalidLink) {
            try await source.download(LibraryFile(id: LibraryFileID(rawValue: "x")), to: FileManager.default.temporaryDirectory.appending(path: "x"))
        }
        #expect(server.requests.isEmpty)
    }
}
