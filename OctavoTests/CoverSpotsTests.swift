import CoreGraphics
import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Where the cover's motion starts or ends (`CoverSpots`): the book's screen
/// on top.
@MainActor
struct CoverSpotsTests {
    static let book = SampleRoutes.book(0)
    static let other = SampleRoutes.book(1)
    static let page = CGRect(x: 0, y: 0, width: 455.5, height: 669)

    private func spot(_ book: SourcedBook = Self.book, frame: CGRect = Self.page) -> CoverSpot {
        CoverSpot(book: book.id, frame: frame, image: nil, title: book.book.title, author: "")
    }

    // A book's screen under another keeps its spot, but only the one on top
    // counts.
    @Test func elsewhereItsTheBooksScreenOnTop() {
        let spots = CoverSpots()
        spots.report(spot(), on: .book(Self.book.id), from: UUID())
        #expect(spots.spot(for: Self.book.id, top: .cover(Self.book)) == spot())
        #expect(spots.spot(for: Self.book.id, top: .cover(Self.other)) == nil)
        #expect(spots.spot(for: Self.book.id, top: SampleRoutes.collections) == nil)
        spots.report(spot(frame: .zero), on: .book(Self.book.id), from: UUID())
        #expect(spots.spot(for: Self.book.id, top: .cover(Self.book)) == nil)
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
