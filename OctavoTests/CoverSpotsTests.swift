import CoreGraphics
import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Where the cover's motion starts or ends (`CoverSpots`): Home's left page
/// when Home shows, else the book's screen on top.
@MainActor
struct CoverSpotsTests {
    static let book = SampleRoutes.book(0)
    static let other = SampleRoutes.book(1)
    static let page = CGRect(x: 0, y: 0, width: 455.5, height: 669)

    private func spot(_ book: SourcedBook = Self.book, frame: CGRect = Self.page) -> CoverSpot {
        CoverSpot(book: book.id, frame: frame, image: nil, title: book.book.title, author: "")
    }

    @Test func onHomeItsHomesSpotForItsBook() {
        let spots = CoverSpots()
        spots.report(spot(), on: .home, from: UUID())
        #expect(spots.spot(for: Self.book.id, onHome: true, top: nil) == spot())
        #expect(spots.spot(for: Self.other.id, onHome: true, top: nil) == nil)
        // Not the book's screen's, though it's the same book.
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.book)) == nil)
    }

    // Home's root stays under a book's screen pushed over it: the same book's
    // screen going mustn't take Home's spot with it.
    @Test func homeAndTheSameBooksScreenKeepTheirOwn() {
        let spots = CoverSpots()
        let home = UUID(), screen = UUID()
        let screenSpot = spot(frame: CGRect(x: 0, y: 0, width: 400, height: 669))
        spots.report(spot(), on: .home, from: home)
        spots.report(screenSpot, on: .book(Self.book.id), from: screen)
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.book)) == screenSpot)
        spots.gone(from: .book(Self.book.id), reporter: screen)
        #expect(spots.spot(for: Self.book.id, onHome: true, top: nil) == spot())
    }

    // Home's page while it loads goes after the page with your book has
    // reported: that mustn't clear it.
    @Test func aPageGoingClearsOnlyItsOwnReport() {
        let spots = CoverSpots()
        let loading = UUID(), loaded = UUID()
        spots.report(spot(Self.other), on: .home, from: loading)
        spots.report(spot(), on: .home, from: loaded)
        spots.gone(from: .home, reporter: loading)
        #expect(spots.spots[.home] != nil)
        spots.gone(from: .home, reporter: loaded)
        #expect(spots.spots[.home] == nil)
    }

    // A book's screen under another keeps its spot, but only the one on top
    // counts.
    @Test func elsewhereItsTheBooksScreenOnTop() {
        let spots = CoverSpots()
        spots.report(spot(), on: .book(Self.book.id), from: UUID())
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.book)) == spot())
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.other)) == nil)
        #expect(spots.spot(for: Self.book.id, onHome: false, top: SampleRoutes.collections) == nil)
        spots.report(spot(frame: .zero), on: .book(Self.book.id), from: UUID())
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.book)) == nil)
    }

    // A fold makes the cover's view again; the old one going mustn't clear
    // the new one's spot.
    @Test func aBookScreenGoingClearsOnlyItsOwnReport() {
        let spots = CoverSpots()
        let before = UUID(), after = UUID()
        let moved = spot(frame: CGRect(x: 0, y: 0, width: 400, height: 669))
        spots.report(spot(), on: .book(Self.book.id), from: before)
        spots.report(moved, on: .book(Self.book.id), from: after)
        spots.gone(from: .book(Self.book.id), reporter: before)
        #expect(spots.spots[.book(Self.book.id)] == moved)
        spots.gone(from: .book(Self.book.id), reporter: after)
        #expect(spots.spots[.book(Self.book.id)] == nil)
    }
}
