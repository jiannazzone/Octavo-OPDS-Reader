import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Going back after a jump (decision 33).
struct ReaderTripTests {
    private let place = ReadingPosition(cfi: "epubcfi(/6/12!/4/2)", fraction: 0.32)

    private func trip() -> ReaderTrip {
        ReaderTrip(place: place, placePage: 312, page: ReadingPosition(cfi: "epubcfi(/6/30!/4/2)", fraction: 0.9))
    }

    @Test func theButtonNamesThePage() {
        #expect(trip().backLabel == "Back to page 312")
    }

    @Test func aPlaceWithNoNumberStillGoesBack() {
        #expect(ReaderTrip(place: place, placePage: nil).backLabel == "Go Back")
    }

    @Test func fiveTurnsForwardIsReadingOn() {
        var trip = trip()
        for turn in 1...5 {
            #expect(!trip.hasReadOn, "after \(turn - 1) turns")
            trip.turned(from: Double(turn) / 100, to: Double(turn + 1) / 100)
        }
        #expect(trip.hasReadOn)
    }

    /// Flipping back and forth in a glossary never gets there.
    @Test func turningBackDoesntCount() {
        var trip = trip()
        for _ in 1...10 {
            trip.turned(from: 0.5, to: 0.51)
            trip.turned(from: 0.51, to: 0.5)
        }
        #expect(trip.turns == 0)
        #expect(!trip.hasReadOn)
    }

    /// A turn at the book's end, or one that went nowhere.
    @Test func aTurnThatDidntMoveDoesntCount() {
        var trip = trip()
        trip.turned(from: 0.5, to: 0.5)
        #expect(trip.turns == 0)
    }

    @Test func anotherJumpStartsTheCountAgainAndKeepsTheWayBack() {
        var trip = trip()
        for _ in 1...4 { trip.turned(from: 0.5, to: 0.51) }
        let glossary = ReadingPosition(cfi: "epubcfi(/6/40!/4/2)", fraction: 0.95)
        trip.landed(on: glossary, fraction: 0.95)
        #expect(trip.turns == 0)
        #expect(trip.page == glossary)
        #expect(trip.pageFraction == 0.95)
        #expect(trip.place == place)
        #expect(trip.placePage == 312)
    }

    @Test func theBooksScreenSaysWhereItOpens() {
        var trip = trip()
        trip.landed(on: trip.page, fraction: 0.905)
        #expect(trip.opensAtLabel == "Opens at 90%")
    }

    // MARK: Saving

    private func store() -> ReadingPositionStore {
        ReadingPositionStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    }

    /// Reopening where you were looking.
    @Test func aTripIsSavedPerBook() {
        let store = store()
        var saved = trip()
        saved.turned(from: 0.5, to: 0.51)
        store.saveTrip(saved, forBook: "book/1")
        #expect(store.trip(forBook: "book/1") == saved)
        #expect(store.trip(forBook: "book/2") == nil)
    }

    @Test func nilEndsATrip() {
        let store = store()
        store.saveTrip(trip(), forBook: "a")
        store.saveTrip(nil, forBook: "a")
        #expect(store.trip(forBook: "a") == nil)
    }

    @Test func aTripIsntTakenForAPosition() throws {
        let store = store()
        store.saveTrip(trip(), forBook: "a")
        #expect(store.progress(forBook: "a") == nil)
    }

    @Test func removingABooksPositionEndsItsTrip() throws {
        let store = store()
        try store.save(place, forBook: "a")
        store.saveTrip(trip(), forBook: "a")
        store.removePosition(forBook: "a")
        #expect(store.trip(forBook: "a") == nil)
    }

    /// Another server: only the kept books' trips stay.
    @Test func removingOtherBooksEndsTheirTrips() {
        let store = store()
        store.saveTrip(trip(), forBook: "kept")
        store.saveTrip(trip(), forBook: "gone")
        store.removeAll(keeping: ["kept"])
        #expect(store.trip(forBook: "kept") != nil)
        #expect(store.trip(forBook: "gone") == nil)
    }
}
