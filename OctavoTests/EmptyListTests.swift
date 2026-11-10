import OctavoKit
import Testing
@testable import Octavo

/// What an empty list says (decision 22, #30), and the list beside it.
struct EmptyListTests {
    private func link(_ rawValue: String) -> LibraryLink {
        LibraryLink(rawValue: rawValue)
    }

    @Test func aListSaysItsServerDecides() {
        let wording = EmptyListWording(kind: .feed, server: "Komga")
        #expect(wording.title == "No books in this list")
        #expect(wording.message == "Books show here when Komga lists them.")
    }

    @Test func aCollectionIsYoursToFill() {
        let wording = EmptyListWording(kind: .collection, server: "BookOrbit")
        #expect(wording.title == "No books in this collection")
        #expect(wording.message == "Books you add to it on BookOrbit show here.")
    }

    // A smart collection is a filter, so nothing is added to it.
    @Test func aSmartCollectionIsTheServersToFill() {
        let wording = EmptyListWording(kind: .smartCollection, server: "BookOrbit")
        #expect(wording.title == "No books in this collection")
        #expect(wording.message == "Books show here when BookOrbit lists them.")
    }

    @Test func aSeriesAndAnAuthorSayWhatTheyAre() {
        #expect(EmptyListWording(kind: .series, server: "BookOrbit").title == "No books in this series")
        #expect(EmptyListWording(kind: .author, server: "BookOrbit").title == "No books by this author")
    }

    @Test func aFilteredListSaysWhatGoesInIt() {
        #expect(EmptyListWording(filter: .unread) == EmptyListWording(title: "No unread books", message: "Books you haven’t started show here."))
        #expect(EmptyListWording(filter: .reading) == EmptyListWording(title: "No books in progress", message: "Books you’re reading show here."))
        #expect(EmptyListWording(filter: .finished) == EmptyListWording(title: "No finished books", message: "Books you finish show here."))
        #expect(EmptyListWording(filter: .all) == nil)
    }

    // The right page's heading matches the shelf's.
    @MainActor @Test func theNewestBooksGoByTheirShelfsName() {
        let latest = LibraryEntry(kind: .feed, title: "Latest books", link: link("latest"))
        let root = LibraryRoot(
            chips: [LibraryEntry(kind: .feed, title: "All", link: link("all")), latest],
            search: .unavailable, recentlyAdded: latest.link
        )
        #expect(LibraryView.newest(root) == latest)
    }

    @MainActor @Test func theNewestBooksAreRecentlyAddedIfTheServerDoesntNameThem() {
        let root = LibraryRoot(chips: [LibraryEntry(kind: .feed, title: "All", link: link("all"))], search: .unavailable, recentlyAdded: link("recent"))
        #expect(LibraryView.newest(root)?.title == "Recently added")
        #expect(LibraryView.newest(root)?.link == link("recent"))
    }

    // BookOrbit's: All, Recently added, Unread, then the rest (#131).
    @MainActor @Test func unreadComesAfterRecentlyAdded() {
        let chips = ["All", "Collections", "Series"].map { LibraryEntry(kind: .feed, title: $0, link: link($0)) }
        let root = LibraryRoot(chips: chips, search: .unavailable, recentlyAdded: link("recent"), unread: link("unread"))
        #expect(LibraryView.sections(root).map(\.title) == ["All", "Recently added", "Unread", "Collections", "Series"])
        #expect(LibraryView.sections(root)[2].link == link("unread"))
    }

    @MainActor @Test func unreadIsSecondWithoutRecentlyAdded() {
        let chips = ["All", "Series"].map { LibraryEntry(kind: .feed, title: $0, link: link($0)) }
        let root = LibraryRoot(chips: chips, search: .unavailable, unread: link("unread"))
        #expect(LibraryView.sections(root).map(\.title) == ["All", "Unread", "Series"])
    }

    // OPDS catalogs have no unread list.
    @MainActor @Test func noUnreadShelfWithoutTheList() {
        let chips = ["All", "Series"].map { LibraryEntry(kind: .feed, title: $0, link: link($0)) }
        let root = LibraryRoot(chips: chips, search: .unavailable, recentlyAdded: link("recent"))
        #expect(LibraryView.sections(root).map(\.title) == ["All", "Recently added", "Series"])
    }

    @MainActor @Test func aServerMayHaveNoNewestBooks() {
        let root = LibraryRoot(chips: [LibraryEntry(kind: .feed, title: "All", link: link("all"))], search: .unavailable)
        #expect(LibraryView.newest(root) == nil)
    }
}
