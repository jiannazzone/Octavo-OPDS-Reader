import Foundation
import OctavoKit
import Testing

/// Bringing the device's bookmarks and the backend's together (decision 18).
struct BookmarkReconciliationTests {
    private let cfiA = "epubcfi(/6/4!/4/44/1:54)"
    private let cfiB = "epubcfi(/6/8!/4/2/1:0)"
    private let cfiC = "epubcfi(/6/12!/4/10/1:7)"

    @Test func aBookmarkMadeElsewhereArrives() {
        let result = BookmarkReconciliation.reconcile(local: [], remote: [SyncedBookmark(id: "7", cfi: cfiA, title: "CHAPTER 2.")])
        #expect(result.bookmarks.count == 1)
        #expect(result.bookmarks.first?.remoteID == "7")
        // Its title is the web reader's, not a chapter.
        #expect(result.bookmarks.first?.chapter == nil)
        #expect(!(result.bookmarks.first?.isDescribed ?? true))
        #expect(result.toAdd.isEmpty)
    }

    @Test func aBookmarkRemovedElsewhereGoes() {
        let synced = LocalBookmark(cfi: cfiA, remoteID: "7", fraction: 0.1)
        let result = BookmarkReconciliation.reconcile(local: [synced], remote: [])
        #expect(result.bookmarks.isEmpty)
    }

    @Test func aBookmarkMadeHereIsAdded() {
        let new = LocalBookmark(cfi: cfiB)
        let result = BookmarkReconciliation.reconcile(local: [new], remote: [SyncedBookmark(id: "7", cfi: cfiA)])
        #expect(result.toAdd == [new.id])
        #expect(result.bookmarks.map(\.cfi) == [cfiB, cfiA])
    }

    // An add that reached the server but whose answer was lost: the same CFI
    // is already there, so it's matched rather than added twice.
    @Test func anAddThatLandedIsMatchedNotRepeated() {
        let new = LocalBookmark(cfi: cfiA, fraction: 0.2)
        let result = BookmarkReconciliation.reconcile(local: [new], remote: [SyncedBookmark(id: "9", cfi: cfiA)])
        #expect(result.toAdd.isEmpty)
        #expect(result.bookmarks.count == 1)
        #expect(result.bookmarks.first?.remoteID == "9")
        #expect(result.bookmarks.first?.fraction == 0.2)
    }

    @Test func aRemovalHereIsSentAndKeptUntilItLands() {
        let removed = LocalBookmark(cfi: cfiA, remoteID: "7", isRemoved: true)
        let result = BookmarkReconciliation.reconcile(local: [removed], remote: [SyncedBookmark(id: "7", cfi: cfiA)])
        #expect(result.bookmarks.map(\.isRemoved) == [true])
        #expect(result.toAdd.isEmpty)

        let landed = BookmarkReconciliation.reconcile(local: [removed], remote: [])
        #expect(landed.bookmarks.isEmpty)
    }

    @Test func aBookmarkMadeAndRemovedOfflineIsForgotten() {
        let result = BookmarkReconciliation.reconcile(local: [LocalBookmark(cfi: cfiA, isRemoved: true)], remote: [])
        #expect(result.bookmarks.isEmpty && result.toAdd.isEmpty)
    }

    @Test func aMovedBookmarkIsPlacedAgain() {
        let synced = LocalBookmark(cfi: cfiA, remoteID: "7", chapter: "Old", excerpt: "Old words", fraction: 0.1)
        let result = BookmarkReconciliation.reconcile(local: [synced], remote: [SyncedBookmark(id: "7", cfi: cfiC)])
        let moved = try! #require(result.bookmarks.first)
        #expect(moved.id == synced.id)
        #expect(moved.cfi == cfiC)
        #expect(!moved.isDescribed && moved.excerpt == nil)
    }
}
