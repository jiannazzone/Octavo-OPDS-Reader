import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// A list of books' Sort and Filter (#131 step 2): the sort remembered per
/// server, and where the Unread shelf's heading goes.
@Suite(.temporaryFiles)
struct ListOrderTests {
    private let bookOrbit = BookOrbitSource(client: BookOrbitClient(baseURL: URL(string: "http://localhost:3300")!))
    private let server = LibrarySourceID(rawValue: "server-1")
    private let other = LibrarySourceID(rawValue: "server-2")

    private func link(_ rawValue: String) -> LibraryLink {
        LibraryLink(rawValue: rawValue)
    }

    @Test func theSortIsRememberedPerServer() {
        let defaults = UserDefaults.testSuite("ListOrderTests")
        #expect(SavedSorts.sort(for: server, in: defaults) == nil)

        SavedSorts.remember(.author, for: server, in: defaults)
        SavedSorts.remember(.recentlyAdded, for: other, in: defaults)
        #expect(SavedSorts.sort(for: server, in: defaults) == .author)
        #expect(SavedSorts.sort(for: other, in: defaults) == .recentlyAdded)

        SavedSorts.forget(server, in: defaults)
        #expect(SavedSorts.sort(for: server, in: defaults) == nil)
        #expect(SavedSorts.sort(for: other, in: defaults) == .recentlyAdded)
    }

    @Test func allAndCollectionsOpenInTheRememberedSort() {
        let defaults = UserDefaults.testSuite("ListOrderTests")
        #expect(SavedSorts.opening(link("books?page=0"), from: bookOrbit, server: server, in: defaults) == link("books?page=0"))

        SavedSorts.remember(.author, for: server, in: defaults)
        #expect(SavedSorts.opening(link("books?page=0"), from: bookOrbit, server: server, in: defaults) == link("books?page=0&sort=author"))
        #expect(SavedSorts.opening(link("collections/1?page=0"), from: bookOrbit, server: server, in: defaults)
            == link("collections/1?page=0&sort=author"))
        // The Unread heading's list keeps its filter.
        #expect(SavedSorts.opening(link("books?page=0&show=unread"), from: bookOrbit, server: server, in: defaults)
            == link("books?page=0&sort=author&show=unread"))
        #expect(SavedSorts.opening(link("books?page=0"), from: bookOrbit, server: other, in: defaults) == link("books?page=0"))
    }

    // A series keeps its reading order, and an author's books their own.
    @Test func seriesAndAuthorsOpenInTheirOwnSort() {
        let defaults = UserDefaults.testSuite("ListOrderTests")
        SavedSorts.remember(.title, for: server, in: defaults)
        #expect(SavedSorts.opening(link("series/3?page=0"), from: bookOrbit, server: server, in: defaults) == link("series/3?page=0"))
        SavedSorts.remember(.recentlyAdded, for: server, in: defaults)
        #expect(SavedSorts.opening(link("authors/5?page=0"), from: bookOrbit, server: server, in: defaults) == link("authors/5?page=0"))
    }

    // OPDS lists have no Sort or Filter yet.
    @Test func aListWithoutAnOrderOpensAsItIs() {
        let defaults = UserDefaults.testSuite("ListOrderTests")
        SavedSorts.remember(.author, for: server, in: defaults)
        #expect(SavedSorts.opening(link("opds/new"), from: StubLibrarySource(), server: server, in: defaults) == link("opds/new"))
        #expect(SavedSorts.opening(link("authors?page=0"), from: bookOrbit, server: server, in: defaults) == link("authors?page=0"))
    }

    @MainActor @Test func theMenusSayWhatEachChoiceIs() {
        #expect([LibrarySort.readingOrder, .title, .author, .recentlyAdded].map(\.title) == ["Reading order", "Title", "Author", "Recently added"])
        #expect(LibraryFilter.allCases.map(\.title) == ["All books", "Unread", "Reading", "Finished"])
    }

    // So taking the filter off leaves All (Adam, 2026-11-09).
    @MainActor @Test func theUnreadHeadingOpensAllWithUnreadPicked() async throws {
        let root = try await bookOrbit.root()
        let unread = try #require(root.unread)
        let opens = LibraryView.opens(root)
        #expect(opens == [unread: LibraryEntry(kind: .feed, title: "All", link: unread)])
        #expect(LibraryView.sections(root).first { $0.link == unread }?.title == "Unread")
    }
}

/// On iPhone's Sort and Filter (#131): Books on iPhone's orders, and each
/// book's status from Octavo's own record.
@MainActor @Suite(.temporaryFiles)
struct OnIPhoneOrderTests {
    @Test func offersTitleAuthorAndRecentlyDownloaded() {
        let order = OnIPhoneOrder.order(.author, .unread)
        #expect(order.sorts.map(OnIPhoneOrder.title) == ["Title", "Author", "Recently downloaded"])
        #expect(order.filters == LibraryFilter.allCases)
        #expect(order.sort == .author)
        #expect(order.filter == .unread)
        // A sort it doesn't offer (a series') is its own.
        #expect(OnIPhoneOrder.order(.readingOrder, .all).sort == .title)
    }

    @Test(arguments: [
        (LibrarySort.title, ["Moby-Dick", "Pride and Prejudice", "The Time Machine"]),
        (.author, ["Pride and Prejudice", "Moby-Dick", "The Time Machine"]),
        (.recentlyAdded, ["Moby-Dick", "The Time Machine", "Pride and Prejudice"]),
    ])
    func sortsAsBooksOnIPhoneDoes(sort: LibrarySort, titles: [String]) {
        #expect(OnIPhoneOrder.sorted(DownloadOrderTests.books, by: sort).map(\.book.book.title) == titles)
    }

    // No place is unread, a place is reading, a Finished mark is finished.
    @Test func eachBooksStatusIsOctavosRecord() {
        let shell = makeShell()
        func book(progress: Double? = nil, finished: Bool? = nil) -> SourcedBook {
            SourcedBook(source: .files, book: LibraryBook(
                id: LibraryBookID(rawValue: UUID().uuidString), title: "Book", progress: progress, isFinished: finished
            ))
        }
        #expect(shell.status(of: book()) == .unread)
        #expect(shell.status(of: book(progress: 0.3)) == .reading)
        #expect(shell.status(of: book(progress: 0.3, finished: true)) == .finished)
        #expect(shell.status(of: book(finished: true)) == .finished)
    }

    // The usual way: a book read on this iPhone, which the server hasn't heard of.
    @Test func aPlaceSavedHereIsReading() throws {
        let shell = makeShell()
        let book = SourcedBook(source: .files, book: LibraryBook(
            id: LibraryBookID(rawValue: "local"), title: "Book",
            files: [LibraryFile(id: LibraryFileID(rawValue: "local.epub"), format: "epub", sizeBytes: 1, isPrimary: true)]
        ))
        #expect(shell.status(of: book) == .unread)
        try shell.places.store.save(ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.2), forBook: try #require(book.storageKey))
        #expect(shell.status(of: book) == .reading)
    }

    // Listing the saved places once gives what reading each would.
    @Test func filteringManyBooksAgreesWithEachBooksStatus() throws {
        let shell = makeShell()
        func book(_ id: String, progress: Double? = nil, finished: Bool? = nil) -> SourcedBook {
            SourcedBook(source: .files, book: LibraryBook(
                id: LibraryBookID(rawValue: id), title: id,
                files: [LibraryFile(id: LibraryFileID(rawValue: "\(id).epub"), format: "epub", sizeBytes: 1, isPrimary: true)],
                progress: progress, isFinished: finished
            ))
        }
        let books = [book("new"), book("listed", progress: 0.4), book("done", finished: true), book("here")]
        try shell.places.store.save(ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.2), forBook: try #require(books[3].storageKey))
        for filter in LibraryFilter.allCases {
            #expect(shell.books(books, showing: filter) == books.filter { filter == .all || shell.status(of: $0) == filter })
        }
        #expect(shell.books(books, showing: .reading).map(\.book.title) == ["listed", "here"])
    }

    @Test func aListsCountNamesItWhenFiltered() {
        #expect(booksLine(1) == "1 book")
        #expect(booksLine(65, in: "All") == "All · 65 books")
    }
}

/// An OPDS list sorted on the iPhone (#131): title, or author then title,
/// filed as the Authors list is.
struct BookOrderTests {
    private static func book(_ title: String, by author: String) -> LibraryBook {
        LibraryBook(id: LibraryBookID(rawValue: title), title: title, authors: [author])
    }

    static let books = [
        book("The Time Machine", by: "H. G. Wells"),
        book("Pride and Prejudice", by: "Jane Austen"),
        book("Emma", by: "Jane Austen"),
        book("Moby-Dick", by: "Herman Melville"),
    ]

    @Test(arguments: [
        (LibrarySort.listOrder, ["The Time Machine", "Pride and Prejudice", "Emma", "Moby-Dick"]),
        (.title, ["Emma", "Moby-Dick", "Pride and Prejudice", "The Time Machine"]),
        (.author, ["Emma", "Pride and Prejudice", "Moby-Dick", "The Time Machine"]),
    ])
    func sortsByTitleOrAuthor(sort: LibrarySort, titles: [String]) {
        #expect(BookOrder.sorted(Self.books, by: sort).map(\.title) == titles)
    }

    @Test func eachListIsArrangedInOnePlace() {
        let bookOrbit = LibraryListOrder(sorts: [.title], filters: LibraryFilter.allCases, sort: .title, filter: .all, takesRememberedSort: true)
        let cops = LibraryListOrder(sorts: [.listOrder, .title], filters: [], sort: .listOrder, filter: .all, takesRememberedSort: false)
        #expect(Arranging(bookOrbit) == .onServer)
        #expect(Arranging(cops) == .sortedOnServer)
        #expect(Arranging(nil) == .here)
    }

    @Test func anOPDSListOpensInTheCatalogsOrder() {
        #expect(!LocalOrder().isOn)
        #expect(LocalOrder(sort: .title).isOn)
        #expect(LocalOrder(filter: .unread).isOn)
        #expect(LocalOrder.sorts == [.listOrder, .title, .author])
    }

    @MainActor @Test func defaultIsTheCatalogsOrder() {
        #expect(LibrarySort.listOrder.title == "Default")
    }

    @Test func countsReadWithSeparators() {
        #expect(booksLine(2_000) == "2,000 books")
    }
}
