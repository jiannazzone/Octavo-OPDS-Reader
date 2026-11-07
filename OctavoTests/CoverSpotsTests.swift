import CoreGraphics
import Foundation
import Testing
@testable import Octavo

/// Where the cover's motion starts or ends (`CoverSpots`): Home's spot once
/// all of it is measured, else the book's screen on top.
@MainActor
struct CoverSpotsTests {
    static let book = SampleRoutes.book(0)
    static let other = SampleRoutes.book(1)
    static let cover = CGRect(x: 47, y: 18, width: 362, height: 543)
    static let page = CGRect(x: 0, y: 0, width: 455.5, height: 669)

    private func homeReport(stripTop: CGFloat? = 588) -> HomeCoverReport {
        HomeCoverReport(book: Self.book, cover: Self.cover, page: Self.page, stripTop: stripTop)
    }

    // A cover moving before its strip was measured left the cover's copy
    // showing.
    @Test func homesSpotWaitsForEveryPart() {
        #expect(homeReport(stripTop: nil).spot == nil)
        #expect(homeReport().spot?.cover == Self.cover)
        var empty = homeReport()
        empty.cover = .zero
        #expect(empty.spot == nil)
        #expect(HomeCoverReport().spot == nil)
    }

    @Test func onHomeItsHomesSpotForItsBook() throws {
        let spots = CoverSpots()
        spots.reportHome(homeReport(), from: UUID())
        spots.bookScreens[Self.book.id] = Self.cover
        let spot = try #require(spots.home.spot)
        #expect(spots.spot(for: Self.book.id, onHome: true, top: nil) == .home(spot))
        #expect(spots.spot(for: Self.other.id, onHome: true, top: nil) == nil)
    }

    // Home's page while it loads goes after the page with your book has
    // reported: that mustn't clear it.
    @Test func aPageGoingClearsOnlyItsOwnReport() {
        let spots = CoverSpots()
        let loading = UUID(), loaded = UUID()
        spots.reportHome(HomeCoverReport(), from: loading)
        spots.reportHome(homeReport(), from: loaded)
        spots.homeGone(loading)
        #expect(spots.home.spot != nil)
        spots.homeGone(loaded)
        #expect(spots.home.spot == nil)
    }

    // A book's screen under another keeps its spot, but only the one on top
    // counts.
    @Test func elsewhereItsTheBooksScreenOnTop() {
        let spots = CoverSpots()
        spots.bookScreens[Self.book.id] = Self.cover
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.book)) == .bookScreen(Self.cover))
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.other)) == nil)
        #expect(spots.spot(for: Self.book.id, onHome: false, top: SampleRoutes.collections) == nil)
        spots.bookScreens[Self.book.id] = .zero
        #expect(spots.spot(for: Self.book.id, onHome: false, top: .cover(Self.book)) == nil)
    }
}
