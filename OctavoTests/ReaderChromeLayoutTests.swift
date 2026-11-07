import CoreGraphics
import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// Who has the strip along the bottom of the page, and where its pieces go
/// (`ReaderChromeLayout`).
struct ReaderChromeLayoutTests {
    static let place = ReaderServerPlace(
        position: ReadingPosition(cfi: "epubcfi(/6/8!/4/2)", fraction: 0.6), fraction: 0.6, chapter: "V", offeredOn: "epubcfi(/6/6!/4/2)"
    )

    private func chrome(_ change: (inout ReaderChromeLayout.State) -> Void = { _ in }) -> ReaderChromeLayout {
        var state = ReaderChromeLayout.State()
        change(&state)
        return ReaderChromeLayout(state: state)
    }

    @Test func aPlainPageHasItsFooter() {
        let plain = chrome()
        #expect(plain.showsFooter)
        #expect(!plain.showsBackBar)
        #expect(plain.footerBar == nil)
        #expect(!plain.hidesFooterChapter)
    }

    // The way back takes the chapter's place and keeps the numbers beside it.
    @Test func theWayBackStaysWithTheFooter() {
        let back = chrome { $0.hasTrip = true }
        #expect(back.showsBackBar)
        #expect(back.showsFooter)
        #expect(back.hidesFooterChapter)
    }

    @Test func notUnderAPanelANoteOrTheTour() {
        #expect(!chrome { $0.hasTrip = true; $0.panelOpen = true }.showsBackBar)
        #expect(!chrome { $0.hasTrip = true; $0.noteOpen = true }.showsBackBar)
        #expect(!chrome { $0.hasTrip = true; $0.inTour = true }.showsBackBar)
    }

    // On one page Search's bar has the strip; on two each has a page.
    @Test func searchTakesTheStripFromTheWayBackOnOnePage() {
        let onePage = chrome { $0.hasTrip = true; $0.searchStepping = true }
        #expect(onePage.footerBar == .search)
        #expect(!onePage.showsBackBar)
        #expect(!onePage.showsFooter)
        let twoPages = chrome { $0.hasTrip = true; $0.searchStepping = true; $0.twoPages = true }
        #expect(twoPages.footerBar == .search)
        #expect(twoPages.showsBackBar)
        #expect(!twoPages.showsFooter)
    }

    // Search's bar comes first; the server's place waits for it to end.
    @Test func searchBeforeTheServersPlace() {
        #expect(chrome { $0.searchStepping = true; $0.serverPlace = Self.place }.footerBar == .search)
    }

    // On one page BookOrbit's capsule stacks over the way back, and the
    // numbers stay; on two they sit under each page and the bar has the strip.
    @Test func theServersPlaceStacksOverTheWayBackOnOnePage() {
        let onePage = chrome { $0.hasTrip = true; $0.serverPlace = Self.place }
        #expect(onePage.footerBar == .serverPlace(Self.place))
        #expect(onePage.stacksOverBackBar)
        #expect(onePage.showsFooter)
        let twoPages = chrome { $0.hasTrip = true; $0.serverPlace = Self.place; $0.twoPages = true }
        #expect(!twoPages.stacksOverBackBar)
        #expect(!twoPages.showsFooter)
    }

    @Test func theProgressBarTakesTheWholeStrip() {
        let bar = chrome { $0.hasTrip = true; $0.serverPlace = Self.place; $0.showsBar = true }
        #expect(bar.footerBar == nil)
        #expect(!bar.showsFooter)
        #expect(bar.showsBackBar, "above the bar")
        // Stepping through Search on one page, the way back stays down even
        // with the bar up.
        #expect(!chrome { $0.hasTrip = true; $0.searchStepping = true; $0.showsBar = true }.showsBackBar)
    }

    @Test func nothingUntilTheBookIsOpen() {
        let loading = chrome { $0.isOpen = false; $0.hasTrip = true; $0.serverPlace = Self.place }
        #expect(!loading.showsBackBar)
        #expect(loading.footerBar == nil)
    }

    // MARK: Where things go

    static let geometry = ReaderGeometry(size: CGSize(width: 466, height: 678), safeArea: ReaderInsets(top: 59, left: 0, bottom: 34, right: 84))
    static let layout = ReaderLayout(bottomInset: 34)

    // The middle of foliate's bottom margin, the line 20 pt tall.
    @Test func theFooterLineIsInTheBottomMargin() {
        let centre = 678 - 34 - ReaderLayout.verticalMargin / 2
        #expect(ReaderChromeLayout.footerLineCentre(in: Self.geometry, layout: Self.layout) == centre)
        #expect(ReaderChromeLayout.footerLineTop(in: Self.geometry, layout: Self.layout) == centre - 10)
    }

    @Test func theWayBackIsOnTheFooterLineOrAboveTheBar() {
        let centre = ReaderChromeLayout.footerLineCentre(in: Self.geometry, layout: Self.layout)
        #expect(chrome { $0.hasTrip = true }.backBarTop(in: Self.geometry, layout: Self.layout, barHeight: 82) == centre - ReaderBackBar.height / 2)
        let above = chrome { $0.hasTrip = true; $0.showsBar = true }.backBarTop(in: Self.geometry, layout: Self.layout, barHeight: 82)
        #expect(above == ReaderLayout.barBottom(in: Self.geometry) - 82 - 8 - ReaderBackBar.height)
    }

    // On the home indicator's edge, 4 pt up; stacked, above the way back.
    @Test func theFooterBarSitsOnTheEdgeOrOverTheWayBack() {
        let edge = max(34, ReaderLayout.edgeInset) + 4
        #expect(chrome { $0.serverPlace = Self.place }.footerBarBottomInset(in: Self.geometry) == edge)
        #expect(chrome { $0.hasTrip = true; $0.serverPlace = Self.place }.footerBarBottomInset(in: Self.geometry) == edge + ReaderBackBar.height + 6)
    }

    // Under the page, or the right page of a spread.
    @Test func theFooterBarRunsUnderItsPage() {
        let one = ReaderChromeLayout.footerBarSpan(in: Self.geometry, layout: Self.layout)
        #expect(one.left == 0)
        #expect(one.width == 466 - 84)
        let spread = ReaderLayout(columns: 2, fold: 455.5...495.5)
        let wide = ReaderGeometry(size: CGSize(width: 951, height: 669), safeArea: ReaderInsets(right: 84))
        let right = ReaderChromeLayout.footerBarSpan(in: wide, layout: spread)
        #expect(right.left == 495.5)
        #expect(right.width == 951 - 84 - 495.5)
    }

    @Test func theTourCardIsAboveASheetOrClearOfTheBar() {
        let bottom = ReaderLayout.barBottom(in: Self.geometry)
        #expect(ReaderChromeLayout.tourCardBottom(in: Self.geometry, sheetHeight: 300, barClearance: 96) == bottom - 300 - 8)
        #expect(ReaderChromeLayout.tourCardBottom(in: Self.geometry, sheetHeight: nil, barClearance: 96) == bottom - 96)
    }
}
