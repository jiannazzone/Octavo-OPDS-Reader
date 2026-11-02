import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// A backend that keeps bookmarks in memory and records what it's sent.
private actor MemoryBookmarkSync: BookmarkSync {
    var remote: [SyncedBookmark]
    private(set) var added: [String] = []
    private(set) var removed: [String] = []
    private var nextID = 100

    init(_ remote: [SyncedBookmark] = []) {
        self.remote = remote
    }

    func bookmarks() async throws -> [SyncedBookmark] { remote }

    func add(cfi: String, title: String) async throws -> SyncedBookmark {
        nextID += 1
        let bookmark = SyncedBookmark(id: String(nextID), cfi: cfi, title: title)
        remote.append(bookmark)
        added.append(title)
        return bookmark
    }

    func remove(id: String) async throws {
        remote.removeAll { $0.id == id }
        removed.append(id)
    }
}

/// One book's bookmarks (decisions 17–18): the page's Bookmark button, the
/// list's order, and syncing with BookOrbit.
@MainActor
@Suite(.temporaryFiles)
struct ReaderBookmarksTests {
    private let store = BookmarkStore(directory: URL.testDirectory.appending(path: "Bookmarks-\(UUID().uuidString)"))
    private let cfiA = "epubcfi(/6/4!/4/44/1:54)"
    private let cfiB = "epubcfi(/6/4!/4/58/1:52)"

    @Test func theButtonMarksThePageThenUnmarksIt() {
        let bookmarks = ReaderBookmarks(bookID: "moby", store: store)
        bookmarks.toggle(pageStart: cfiA, place: BookmarkPlace(fraction: 0.03, chapter: "CHAPTER 1. Loomings.", excerpt: "the dreamiest"))
        #expect(bookmarks.pageIsBookmarked)
        #expect(bookmarks.list.map(\.cfi) == [cfiA])

        bookmarks.toggle(pageStart: cfiA, place: nil)
        #expect(!bookmarks.pageIsBookmarked)
        #expect(bookmarks.list.isEmpty)
        #expect(bookmarks.all.isEmpty)
    }

    @Test func bookmarksAreKeptOnTheIPhone() {
        let bookmarks = ReaderBookmarks(bookID: "moby", store: store)
        bookmarks.add(cfi: cfiA, place: BookmarkPlace(fraction: 0.03, chapter: "CHAPTER 1. Loomings.", excerpt: nil))
        let reopened = ReaderBookmarks(bookID: "moby", store: store)
        #expect(reopened.list.map(\.cfi) == [cfiA])
        #expect(reopened.list.first?.chapter == "CHAPTER 1. Loomings.")
    }

    @Test func theListFollowsTheBook() {
        let bookmarks = ReaderBookmarks(bookID: "moby", store: store)
        bookmarks.add(cfi: cfiB, place: BookmarkPlace(fraction: 0.04))
        bookmarks.add(cfi: cfiA, place: BookmarkPlace(fraction: 0.03))
        bookmarks.add(cfi: "epubcfi(/6/8!/4/2/1:0)", place: nil)
        #expect(bookmarks.list.map(\.cfi) == [cfiA, cfiB, "epubcfi(/6/8!/4/2/1:0)"])
        #expect(bookmarks.undescribed.count == 1)
    }

    // Made offline: the next open sends it, and keeps the server's ID.
    @Test func aRefreshSendsWhatWasMadeOfflineAndBringsInTheRest() async {
        let offline = ReaderBookmarks(bookID: "moby", store: store)
        offline.add(cfi: cfiA, place: BookmarkPlace(fraction: 0.03, chapter: "CHAPTER 1. Loomings."))

        let sync = MemoryBookmarkSync([SyncedBookmark(id: "7", cfi: cfiB, title: "From the web")])
        let bookmarks = ReaderBookmarks(bookID: "moby", store: store, sync: sync)
        await bookmarks.refresh()

        #expect(await sync.added == ["CHAPTER 1. Loomings."])
        #expect(Set(bookmarks.list.map(\.cfi)) == [cfiA, cfiB])
        #expect(bookmarks.list.allSatisfy { $0.remoteID != nil })
        #expect(bookmarks.undescribed.map(\.cfi) == [cfiB])
    }

    @Test func aRemovalReachesTheServerAndIsThenForgotten() async {
        let sync = MemoryBookmarkSync([SyncedBookmark(id: "7", cfi: cfiA)])
        let bookmarks = ReaderBookmarks(bookID: "moby", store: store, sync: sync)
        await bookmarks.refresh()
        let synced = try! #require(bookmarks.list.first)

        bookmarks.remove(synced.id)
        #expect(bookmarks.list.isEmpty)
        await bookmarks.refresh()
        #expect(await sync.removed == ["7"])
        #expect(bookmarks.all.isEmpty)
    }

    @Test func placingAgainKeepsTheRest() {
        let bookmarks = ReaderBookmarks(bookID: "moby", store: store)
        let bookmark = bookmarks.add(cfi: cfiA, place: BookmarkPlace(fraction: 0.031, chapter: "CHAPTER 1. Loomings.", excerpt: "the dreamiest"))
        bookmarks.place([bookmark.id: 0.0348])
        #expect(bookmarks.list.first?.fraction == 0.0348)
        #expect(bookmarks.list.first?.excerpt == "the dreamiest")
    }

    @Test func theServerTitleIsTheChapterElseTheFirstWords() {
        #expect(ReaderBookmarks.title(for: LocalBookmark(cfi: cfiA, chapter: "CHAPTER 2.", excerpt: "I stuffed")) == "CHAPTER 2.")
        #expect(ReaderBookmarks.title(for: LocalBookmark(cfi: cfiA, excerpt: String(repeating: "w", count: 100))).count == 80)
        #expect(ReaderBookmarks.title(for: LocalBookmark(cfi: cfiA)) == "Bookmark")
    }

    // MARK: Contents

    @Test func contentsArriveAgainPlacedToTheCharacter() throws {
        let json = #"{"type":"contents","toc":[{"label":"CHAPTER 2. The Carpet-Bag.","fraction":0.0421,"href":"text.xhtml#ch2","depth":0},{"label":"Part one","fraction":null,"href":"text.xhtml#p1","depth":1}]}"#
        guard case .contents(let entries) = try ReaderMessage.decode(json) else {
            Issue.record("Expected contents")
            return
        }
        #expect(entries.map(\.href) == ["text.xhtml#ch2", "text.xhtml#p1"])
        #expect(entries.map(\.depth) == [0, 1])
        #expect(entries.last?.fraction == nil)
    }

    @Test func aContentsPageCountsLikeTheFooter() {
        #expect(ReaderModel.page(at: 0.0421, total: 974) == 42)
        #expect(ReaderModel.page(at: 1, total: 974) == 974)
        #expect(ReaderModel.page(at: 0.5, total: nil) == nil)
    }
}
