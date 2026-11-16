import Foundation
import OctavoKit
import Testing

/// Bringing the device's highlights and the backend's together (#125).
struct HighlightReconciliationTests {
    private let cfiA = "epubcfi(/6/4!/4/38/2,/1:143,/1:150)"
    private let cfiB = "epubcfi(/6/8!/4/2,/1:0,/1:20)"
    private let earlier = Date(timeIntervalSince1970: 1_000)
    private let later = Date(timeIntervalSince1970: 2_000)
    private let latest = Date(timeIntervalSince1970: 3_000)

    @Test func oneMadeElsewhereArrives() {
        let result = HighlightReconciliation.reconcile(local: [], remote: [
            SyncedHighlight(id: "7", cfi: cfiA, text: "Collins", color: "#4ADE80", note: "Ha", chapter: "Chapter 13", updatedAt: earlier),
        ])
        let highlight = try? #require(result.highlights.first)
        #expect(highlight?.remoteID == "7")
        #expect(highlight?.color == "#4ADE80")
        #expect(highlight?.note == "Ha")
        #expect(highlight?.chapter == "Chapter 13")
        #expect(highlight?.syncedUpdatedAt == earlier)
        #expect(highlight?.isDescribed == false)
        #expect(result.toAdd.isEmpty && result.toUpdate.isEmpty)
    }

    @Test func oneWithNoColourGetsYellow() {
        let result = HighlightReconciliation.reconcile(local: [], remote: [SyncedHighlight(id: "7", cfi: cfiA, text: "Collins")])
        #expect(result.highlights.first?.color == LocalHighlight.defaultColor)
    }

    @Test func oneThisFileDoesntHaveIsKeptWithNoRange() {
        let result = HighlightReconciliation.reconcile(local: [], remote: [SyncedHighlight(id: "7", cfi: nil, text: "It is a truth", chapter: "Chapter 1")])
        #expect(result.highlights.first?.cfi == nil)
        #expect(result.highlights.first?.chapter == "Chapter 1")
    }

    // Deleted elsewhere wins, even over an edit made here.
    @Test func oneDeletedElsewhereGoes() {
        let edited = LocalHighlight(cfi: cfiA, text: "Collins", note: "mine", remoteID: "7", unsent: [.note], editedAt: latest)
        let result = HighlightReconciliation.reconcile(local: [edited], remote: [])
        #expect(result.highlights.isEmpty)
        #expect(result.toUpdate.isEmpty)
    }

    @Test func oneMadeHereIsAdded() {
        let new = LocalHighlight(cfi: cfiB, text: "Chapter")
        let result = HighlightReconciliation.reconcile(local: [new], remote: [SyncedHighlight(id: "7", cfi: cfiA, text: "Collins")])
        #expect(result.toAdd == [new.id])
        #expect(result.highlights.map(\.cfi) == [cfiB, cfiA])
    }

    // An add that reached the server but whose answer was lost: the same
    // range and words are already there, so it's matched, not added twice.
    @Test func anAddThatLandedIsMatchedNotRepeated() {
        let new = LocalHighlight(cfi: cfiA, text: "Collins", fraction: 0.2)
        let result = HighlightReconciliation.reconcile(local: [new], remote: [SyncedHighlight(id: "9", cfi: cfiA, text: "Collins", updatedAt: earlier)])
        #expect(result.toAdd.isEmpty)
        #expect(result.highlights.count == 1)
        #expect(result.highlights.first?.remoteID == "9")
        #expect(result.highlights.first?.id == new.id)
        #expect(result.highlights.first?.fraction == 0.2)
    }

    @Test func theSameRangeWithOtherWordsIsntALandedAdd() {
        let new = LocalHighlight(cfi: cfiA, text: "Collins")
        let result = HighlightReconciliation.reconcile(local: [new], remote: [SyncedHighlight(id: "9", cfi: cfiA, text: "Something else")])
        #expect(result.toAdd == [new.id])
        #expect(result.highlights.count == 2)
    }

    @Test func oneRemovedHereIsKeptUntilTheServerHears() {
        let removed = LocalHighlight(cfi: cfiA, text: "Collins", remoteID: "7", isRemoved: true)
        let result = HighlightReconciliation.reconcile(local: [removed], remote: [SyncedHighlight(id: "7", cfi: cfiA, text: "Collins")])
        #expect(result.highlights.map(\.isRemoved) == [true])
    }

    @Test func oneRemovedHereBeforeItWasSentIsForgotten() {
        let removed = LocalHighlight(cfi: cfiA, text: "Collins", isRemoved: true)
        let result = HighlightReconciliation.reconcile(local: [removed], remote: [])
        #expect(result.highlights.isEmpty)
        #expect(result.toAdd.isEmpty)
    }

    @Test func anEditHereIsSentWhenTheServerHasntChanged() {
        let edited = LocalHighlight(cfi: cfiA, text: "Collins", color: "#38BDF8", remoteID: "7", unsent: [.color], editedAt: later, syncedUpdatedAt: earlier)
        let result = HighlightReconciliation.reconcile(local: [edited], remote: [
            SyncedHighlight(id: "7", cfi: cfiA, text: "Collins", color: "#FACC15", note: "theirs", updatedAt: earlier),
        ])
        #expect(result.toUpdate == [edited.id])
        #expect(result.highlights.first?.color == "#38BDF8")
        #expect(result.highlights.first?.note == "theirs")
    }

    @Test func aLaterEditElsewhereWins() {
        let edited = LocalHighlight(cfi: cfiA, text: "Collins", color: "#38BDF8", remoteID: "7", unsent: [.color], editedAt: later, syncedUpdatedAt: earlier)
        let result = HighlightReconciliation.reconcile(local: [edited], remote: [
            SyncedHighlight(id: "7", cfi: cfiA, text: "Collins", color: "#F472B6", updatedAt: latest),
        ])
        #expect(result.toUpdate.isEmpty)
        #expect(result.highlights.first?.color == "#F472B6")
        #expect(result.highlights.first?.unsent == [])
        #expect(result.highlights.first?.syncedUpdatedAt == latest)
    }

    @Test func aLaterEditHereWins() {
        let edited = LocalHighlight(cfi: cfiA, text: "Collins", note: "mine", remoteID: "7", unsent: [.note], editedAt: latest, syncedUpdatedAt: earlier)
        let result = HighlightReconciliation.reconcile(local: [edited], remote: [
            SyncedHighlight(id: "7", cfi: cfiA, text: "Collins", color: "#F472B6", note: "theirs", updatedAt: later),
        ])
        #expect(result.toUpdate == [edited.id])
        #expect(result.highlights.first?.note == "mine")
        // What wasn't changed here comes from the server.
        #expect(result.highlights.first?.color == "#F472B6")
    }

    @Test func aTieGoesToTheServer() {
        let edited = LocalHighlight(cfi: cfiA, text: "Collins", note: "mine", remoteID: "7", unsent: [.note], editedAt: later, syncedUpdatedAt: earlier)
        let result = HighlightReconciliation.reconcile(local: [edited], remote: [
            SyncedHighlight(id: "7", cfi: cfiA, text: "Collins", note: "theirs", updatedAt: later),
        ])
        #expect(result.toUpdate.isEmpty)
        #expect(result.highlights.first?.note == "theirs")
    }

    // A colour another app stored stays as it is.
    @Test func theServersColourIsKeptAsItIs() {
        let synced = LocalHighlight(cfi: cfiA, text: "Collins", remoteID: "7", syncedUpdatedAt: earlier)
        let result = HighlightReconciliation.reconcile(local: [synced], remote: [
            SyncedHighlight(id: "7", cfi: cfiA, text: "Collins", color: "yellow", updatedAt: later),
        ])
        #expect(result.highlights.first?.color == "yellow")
        #expect(result.toUpdate.isEmpty)
    }

    @Test func aRangeThatMovedIsPlacedAgain() {
        let placed = LocalHighlight(cfi: cfiA, text: "Collins", remoteID: "7", syncedUpdatedAt: earlier, fraction: 0.3)
        let result = HighlightReconciliation.reconcile(local: [placed], remote: [SyncedHighlight(id: "7", cfi: nil, text: "Collins", updatedAt: earlier)])
        #expect(result.highlights.first?.cfi == nil)
        #expect(result.highlights.first?.fraction == nil)
    }

    @Test func theUnsentEditIsWhatChanged() {
        let highlight = LocalHighlight(cfi: cfiA, text: "Collins", color: "#38BDF8", note: nil, unsent: [.note])
        #expect(highlight.edit == HighlightEdit(note: .some(nil)))
        #expect(LocalHighlight(cfi: cfiA, text: "x", color: "#38BDF8", unsent: [.color]).edit == HighlightEdit(color: "#38BDF8"))
    }
}
