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
