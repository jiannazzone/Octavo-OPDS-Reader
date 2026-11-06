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

    // MARK: Your place

    @Test func yourPlaceIsItsOwnSpellingOrTheServers() {
        var trip = trip()
        #expect(trip.isPlace(place))
        let server = ReadingPosition(cfi: "epubcfi(/6/12!/4/8)", fraction: 0.32)
        #expect(!trip.isPlace(server))
        trip.placeOnServer = server.cfi
        #expect(trip.isPlace(server))
    }

    /// A page away is still another reader's move.
    @Test func aNearbyPlaceIsntYourPlace() {
        #expect(!trip().isPlace(ReadingPosition(cfi: "epubcfi(/6/12!/4/4)", fraction: 0.3201)))
    }

    @Test func nothingToOpenAtIsntYourPlace() {
        #expect(!trip().isPlace(nil))
    }

    /// A percentage alone goes by the number.
    @Test func withNoCFIsItGoesByTheNumber() {
        let percentage = ReaderTrip(place: ReadingPosition(cfi: nil, fraction: 0.32), placePage: nil)
        #expect(percentage.isPlace(ReadingPosition(cfi: nil, fraction: 0.3201)))
        #expect(!percentage.isPlace(ReadingPosition(cfi: nil, fraction: 0.5)))
        #expect(!trip().isPlace(ReadingPosition(cfi: nil, fraction: 0.32)))
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

    /// A server that can't come back: its books' trips go, the others' stay.
    @Test func removingAServersBooksEndsTheirTrips() {
        let store = store()
        let gone = LibrarySourceID(rawValue: "gone")
        store.saveTrip(trip(), forBook: "kept")
        store.saveTrip(trip(), forBook: "gone.book")
        store.removeAll(of: gone)
        #expect(store.trip(forBook: "kept") != nil)
        #expect(store.trip(forBook: "gone.book") == nil)
    }
}
