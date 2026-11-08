import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Octavo

/// Hinge → page layout. Geometry from the iPhone Duo simulator (iOS 27.1):
/// the inner display's page is 951×493 with the hinge line at x 475.5, and
/// the division region is that line plus 20pt margins each side.
struct ReaderLayoutTests {
    static let fold = CGRect(x: 455.5, y: -176, width: 40, height: 669)

    static func unfolded(active: Bool, fold: CGRect = fold) -> ReaderGeometry {
        ReaderGeometry(size: CGSize(width: 951, height: 493), divisions: [.init(frame: fold, isActive: active)])
    }

    static let folded = ReaderGeometry(size: CGSize(width: 466, height: 502))

    @Test func foldedIsOnePage() {
        #expect(ReaderLayout(posture: .closed, geometry: Self.folded).columns == 1)
    }

    // While closing, the region briefly reports for the inner display.
    @Test func closedIgnoresALeftoverFold() {
        #expect(ReaderLayout(posture: .closed, geometry: Self.unfolded(active: true)).columns == 1)
    }

    @Test(arguments: [ReaderPosture.open, .halfOpen], [false, true])
    func unfoldedIsASpreadAroundTheFold(posture: ReaderPosture, active: Bool) throws {
        let layout = ReaderLayout(posture: posture, geometry: Self.unfolded(active: active))
        #expect(layout.columns == 2)
        #expect(layout.leftInset == 0)
        #expect(layout.rightInset == 0)
        #expect(layout.fold == 455.5...495.5)
        let gap = try #require(layout.gap(inReaderWidth: 951))
        #expect(gap.lowerBound <= 455.5)
        #expect(gap.upperBound >= 495.5)
        #expect(abs((gap.lowerBound + gap.upperBound) / 2 - 475.5) < 0.001)
    }

    @Test func spreadKeepsFoliatesSpacingWhenTheFoldIsNarrower() throws {
        let layout = ReaderLayout(posture: .open, geometry: Self.unfolded(active: false))
        // 40 of 951 is 4.3%, under foliate's 7%: 7% of 951, to the point.
        let gap = try #require(layout.gap(inReaderWidth: 951))
        #expect(Self.near(gap.upperBound - gap.lowerBound, 67, within: 0.01))
    }

    @Test func spreadWidensTheGapForAWideFold() throws {
        let wide = CGRect(x: 425.5, y: 0, width: 100, height: 493)
        let layout = ReaderLayout(posture: .open, geometry: Self.unfolded(active: true, fold: wide))
        let gap = try #require(layout.gap(inReaderWidth: 951))
        #expect(gap.lowerBound <= 425.5)
        #expect(gap.upperBound >= 525.5)
        #expect(try #require(layout.gapPercent) > ReaderLayout.defaultGapPercent)
    }

    // foliate centres its gap in its view, so an off-centre fold needs the
    // view trimmed on the far side.
    @Test(arguments: [395.5, 555.5])
    func offCentreFoldMovesTheViewOntoIt(foldX: Double) throws {
        let fold = CGRect(x: foldX, y: -176, width: 40, height: 669)
        let layout = ReaderLayout(posture: .open, geometry: Self.unfolded(active: true, fold: fold))
        let gap = try #require(layout.gap(inReaderWidth: 951))
        #expect(abs((gap.lowerBound + gap.upperBound) / 2 - Double(fold.midX)) < 0.001)
        #expect(gap.lowerBound <= Double(fold.minX))
        #expect(gap.upperBound >= Double(fold.maxX))
        #expect(min(layout.leftInset, layout.rightInset) == 0)
        #expect(layout.leftInset + layout.rightInset == abs(951 - 2 * Double(fold.midX)))
    }

    @Test func textWidthFitsExactlyTwoColumns() throws {
        let layout = ReaderLayout(posture: .open, geometry: Self.unfolded(active: false))
        #expect(layout.maxInlineSize == 476)
    }

    // Turned sideways, the fold runs across the page: one column. (Owner:
    // the likely default; a setting later.)
    @Test func foldAcrossThePageIsOnePage() {
        let geometry = ReaderGeometry(
            size: CGSize(width: 493, height: 951),
            divisions: [.init(frame: CGRect(x: -176, y: 455.5, width: 669, height: 40), isActive: true)]
        )
        #expect(ReaderLayout(posture: .halfOpen, geometry: geometry).columns == 1)
    }

    @Test func foldTooCloseToAnEdgeIsOnePage() {
        let nearEdge = CGRect(x: 100, y: -176, width: 40, height: 669)
        #expect(ReaderLayout(posture: .open, geometry: Self.unfolded(active: true, fold: nearEdge)).columns == 1)
    }

    @Test func openWithoutARegionSplitsALandscapePageInTheMiddle() throws {
        let layout = ReaderLayout(posture: .open, geometry: ReaderGeometry(size: CGSize(width: 951, height: 493)))
        #expect(layout.columns == 2)
        #expect(layout.fold == nil)
        let gap = try #require(layout.gap(inReaderWidth: 951))
        #expect(abs((gap.lowerBound + gap.upperBound) / 2 - 475.5) < 0.001)
    }

    // During an unfold the hinge says open before the page has its new size.
    @Test func openWithAPortraitPageAndNoRegionIsOnePage() {
        #expect(ReaderLayout(posture: .open, geometry: ReaderGeometry(size: CGSize(width: 466, height: 510))).columns == 1)
    }

    @Test func noHingeLeavesTheColumnsToFoliate() {
        #expect(ReaderLayout(posture: .noHinge, geometry: ReaderGeometry(size: CGSize(width: 1024, height: 768))).columns == nil)
        #expect(ReaderLayout(posture: .noHinge, geometry: nil).columns == nil)
    }

    // Without a hinge report, the fold's region alone still makes a spread.
    @Test(arguments: [false, true])
    func noHingeStillFollowsTheFold(active: Bool) {
        let layout = ReaderLayout(posture: .noHinge, geometry: Self.unfolded(active: active))
        #expect(layout.columns == 2)
        #expect(layout.fold == 455.5...495.5)
    }

    // MARK: Edge to edge, the text out of the side column (decision 8)

    /// The full displays with their safe areas, as the simulator reports
    /// them: the side column (84 pt) and the home indicator (34 pt).
    static let foldedScreen = ReaderGeometry(
        size: CGSize(width: 466, height: 678),
        safeArea: ReaderInsets(top: 0, left: 0, bottom: 34, right: 84)
    )

    static func unfoldedScreen(active: Bool = false) -> ReaderGeometry {
        ReaderGeometry(
            size: CGSize(width: 951, height: 669),
            divisions: [.init(frame: CGRect(x: 455.5, y: 0, width: 40, height: 669), isActive: active)],
            safeArea: ReaderInsets(top: 0, left: 0, bottom: 34, right: 84)
        )
    }

    static func near(_ a: Double, _ b: Double, within tolerance: Double = 0.5) -> Bool {
        abs(a - b) <= tolerance
    }

    // Frame 07: the text runs 27–355 pt on the 382 pt content area.
    @Test func foldedTextStaysInTheContentArea() throws {
        let layout = ReaderLayout(posture: .closed, geometry: Self.foldedScreen)
        #expect(layout.leftInset == 0)
        #expect(layout.rightInset == 84)
        #expect(layout.bottomInset == 34)
        let text = try #require(layout.textColumns(inReaderWidth: 466)?.first)
        #expect(Self.near(text.lowerBound, 27, within: 0.01))
        #expect(Self.near(text.upperBound, 355, within: 0.01))
    }

    // Frame 09: the spread centred on the hinge, the left edge giving up the
    // column's 84 pt; text 139–448 and 503–812.
    @Test(arguments: [false, true])
    func unfoldedSpreadMatchesTheColumnOnTheLeft(active: Bool) throws {
        let layout = ReaderLayout(posture: active ? .halfOpen : .open, geometry: Self.unfoldedScreen(active: active))
        #expect(layout.leftInset == 84)
        #expect(layout.rightInset == 84)
        let columns = try #require(layout.textColumns(inReaderWidth: 951))
        #expect(columns.count == 2)
        #expect(Self.near(columns[0].lowerBound, 139, within: 0.01))
        #expect(Self.near(columns[0].upperBound, 448, within: 0.01))
        #expect(Self.near(columns[1].lowerBound, 503, within: 0.01))
        #expect(Self.near(columns[1].upperBound, 812, within: 0.01))
        #expect(columns[0].upperBound <= 455.5)
        #expect(columns[1].lowerBound >= 495.5)
    }

    // The five steps folded: the left margin, and how far the text ends
    // short of the column at 382. Narrow's margin lies under the column, and
    // two fifths of the next step's.
    @Test(arguments: [
        (ReaderMargins.narrow, 18.0, 0.0), (.mediumNarrow, 23.203125, 13.796875),
        (.medium, 27, 27), (.mediumWide, 32, 32), (.wide, 38, 38),
    ])
    func foldedMargins(margins: ReaderMargins, left: Double, right: Double) throws {
        let layout = ReaderLayout(posture: .closed, geometry: Self.foldedScreen, margins: margins)
        let text = try #require(layout.textColumns(inReaderWidth: 466)?.first)
        #expect(Self.near(text.lowerBound, left, within: 0.01))
        #expect(Self.near(382 - text.upperBound, right, within: 0.01))
    }

    // The five steps unfolded: the outer margins from the column's edge (and
    // its mirror on the left), and the gutter. Narrow's gutter is a point
    // wider than the 40 pt hinge.
    @Test(arguments: [
        (ReaderMargins.narrow, 0.0, 41.0), (.mediumNarrow, 29, 48),
        (.medium, 55, 55), (.mediumWide, 67, 67), (.wide, 78, 78),
    ])
    func unfoldedMarginsAndGutter(margins: ReaderMargins, outer: Double, gutter: Double) throws {
        let layout = ReaderLayout(posture: .open, geometry: Self.unfoldedScreen(), margins: margins)
        let columns = try #require(layout.textColumns(inReaderWidth: 951))
        #expect(Self.near(columns[1].lowerBound - columns[0].upperBound, gutter, within: 0.01))
        // Half a point clear of the hinge each side.
        #expect(columns[0].upperBound <= 455)
        #expect(columns[1].lowerBound >= 496)
        // Still centred on the hinge.
        #expect(Self.near((columns[0].upperBound + columns[1].lowerBound) / 2, 475.5, within: 0.01))
        #expect(Self.near(columns[0].lowerBound, 84 + outer, within: 0.01))
        #expect(Self.near(columns[1].upperBound, 867 - outer, within: 0.01))
    }

    // Right to left the column is on the left: each step mirrors its folded
    // layout, and the view's rounding never puts text under the column.
    // Unfolded, the spread is the same both ways.
    @Test(arguments: ReaderMargins.allCases)
    func rightToLeftMirrorsTheSteps(margins: ReaderMargins) throws {
        let folded = ReaderGeometry(size: CGSize(width: 466, height: 678), safeArea: ReaderInsets(top: 0, left: 84, bottom: 34, right: 0))
        let layout = ReaderLayout(posture: .closed, geometry: folded, margins: margins)
        let mirrored = ReaderLayout(posture: .closed, geometry: Self.foldedScreen, margins: margins)
        let text = try #require(layout.textColumns(inReaderWidth: 466)?.first)
        let mirror = try #require(mirrored.textColumns(inReaderWidth: 466)?.first)
        #expect(text.lowerBound >= 84)
        #expect(Self.near(text.lowerBound - 84, 382 - mirror.upperBound, within: 0.25))
        #expect(Self.near(466 - text.upperBound, mirror.lowerBound, within: 0.25))
        let (view, page) = Self.foliatePage(layout, readerWidth: 466)
        #expect(view == view.rounded())
        #expect(page == page.rounded())

        var unfolded = Self.unfoldedScreen()
        unfolded.safeArea = ReaderInsets(top: 0, left: 84, bottom: 34, right: 0)
        let spread = try #require(ReaderLayout(posture: .open, geometry: unfolded, margins: margins).textColumns(inReaderWidth: 951))
        let spreadMirror = try #require(ReaderLayout(posture: .open, geometry: Self.unfoldedScreen(), margins: margins).textColumns(inReaderWidth: 951))
        #expect(spread == spreadMirror)
    }

    // Each step between two of the first three sits halfway between them on
    // the page, folded and unfolded, to within 2 pt a side.
    @Test(arguments: [(ReaderMargins.mediumNarrow, ReaderMargins.narrow, ReaderMargins.medium), (.mediumWide, .medium, .wide)])
    func newStepsAreHalfway(step: ReaderMargins, below: ReaderMargins, above: ReaderMargins) throws {
        for (geometry, posture, width) in [(Self.foldedScreen, ReaderPosture.closed, 466.0), (Self.unfoldedScreen(), .open, 951)] {
            func text(_ margins: ReaderMargins) throws -> ClosedRange<Double> {
                let columns = try #require(ReaderLayout(posture: posture, geometry: geometry, margins: margins).textColumns(inReaderWidth: width))
                return columns[0].lowerBound...columns[columns.count - 1].upperBound
            }
            let (middle, low, high) = (try text(step), try text(below), try text(above))
            #expect(Self.near(middle.lowerBound, (low.lowerBound + high.lowerBound) / 2, within: 2))
            #expect(Self.near(middle.upperBound, (low.upperBound + high.upperBound) / 2, within: 2))
        }
    }

    // Turned sideways the column is a band along the top: one column
    // across the fold (decision 12), clear of the band.
    @Test func sidewaysKeepsClearOfTheTopBand() throws {
        let geometry = ReaderGeometry(
            size: CGSize(width: 669, height: 951),
            divisions: [.init(frame: CGRect(x: 0, y: 455.5, width: 669, height: 40), isActive: false)],
            safeArea: ReaderInsets(top: 82, left: 0, bottom: 34, right: 0)
        )
        let layout = ReaderLayout(posture: .open, geometry: geometry)
        #expect(layout.columns == 1)
        #expect(layout.topInset == 82)
        #expect(layout.bottomInset == 34)
        #expect(layout.leftInset == 0)
        #expect(layout.rightInset == 0)
    }

    // foliate caps a column at max-inline-size (720 px) and centres it.
    @Test func aWideSinglePageCentresItsCappedText() throws {
        let geometry = ReaderGeometry(size: CGSize(width: 1200, height: 800))
        let layout = ReaderLayout(posture: .closed, geometry: geometry)
        let text = try #require(layout.textColumns(inReaderWidth: 1200)?.first)
        #expect(Self.near(text.upperBound - text.lowerBound, 720 * (1 - 0.07 / 0.93)))
        #expect(Self.near((text.lowerBound + text.upperBound) / 2, 600))
    }

    @Test func insetsReachTheBridge() {
        let arguments = ReaderLayout(posture: .closed, geometry: Self.foldedScreen).scriptArguments
        #expect(arguments["rightInset"] as? Double == 84)
        #expect(arguments["bottomInset"] as? Double == 34)
        #expect(arguments["topInset"] as? Double == 0)
        // 27 pt of the 382 pt view.
        #expect(Self.near(arguments["gapPercent"] as? Double ?? 0, 2700.0 / 382, within: 0.01))
    }

    @Test func safeAreaInPhysicalDirections() {
        let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 84)
        #expect(ReaderInsets(insets, layoutDirection: .leftToRight) == ReaderInsets(top: 1, left: 2, bottom: 3, right: 84))
        #expect(ReaderInsets(insets, layoutDirection: .rightToLeft) == ReaderInsets(top: 1, left: 84, bottom: 3, right: 2))
    }

    @Test func activeRegionWinsOverAnInactiveOne() {
        let geometry = ReaderGeometry(size: CGSize(width: 951, height: 493), divisions: [
            .init(frame: CGRect(x: 395.5, y: -176, width: 40, height: 669), isActive: false),
            .init(frame: Self.fold, isActive: true),
        ])
        #expect(ReaderLayout(posture: .open, geometry: geometry).fold == 455.5...495.5)
    }

    @Test func scriptArgumentsUseNullForFoliatesDefaults() {
        let arguments = ReaderLayout.single.scriptArguments
        #expect(arguments["columns"] as? Int == 1)
        #expect(arguments["gapPercent"] is NSNull)
        #expect(arguments["maxInlineSize"] is NSNull)
        #expect(arguments["fold"] is NSNull)
        #expect(arguments["leftInset"] as? Double == 0)

        let spread = ReaderLayout(posture: .open, geometry: Self.unfolded(active: false)).scriptArguments
        #expect(spread["columns"] as? Int == 2)
        #expect(Self.near(spread["gapPercent"] as? Double ?? 0, 6700.0 / 951, within: 0.01))
        #expect(spread["fold"] as? [Double] == [455.5, 495.5])
    }

    // MARK: A whole page (text on the hinge, docs/notes/reader-page.md)

    static let sideways = ReaderGeometry(
        size: CGSize(width: 669, height: 951),
        divisions: [.init(frame: CGRect(x: 0, y: 455.5, width: 669, height: 40), isActive: false)],
        safeArea: ReaderInsets(top: 82, left: 0, bottom: 34, right: 0)
    )

    /// foliate's page width as WebKit lays it out: the view less its two
    /// half-gaps, each truncated to 1/64 pt.
    static func foliatePage(_ layout: ReaderLayout, readerWidth: Double) -> (view: Double, page: Double) {
        let view = readerWidth - layout.leftInset - layout.rightInset
        let halfGap = ((layout.gapPercent ?? 7) / 100 * view / 2 * 64).rounded(.down) / 64
        return (view, view - 2 * halfGap)
    }

    // WebKit scrolls to whole points, so foliate's page must be whole or
    // each page lands up to a point right of where the layout put it.
    @Test(arguments: ReaderMargins.allCases, [ReaderPosture.closed, .open, .halfOpen])
    func foliatesPageIsWholePoints(margins: ReaderMargins, posture: ReaderPosture) {
        let geometry = posture == .closed ? Self.foldedScreen : Self.unfoldedScreen(active: posture == .halfOpen)
        let layout = ReaderLayout(posture: posture, geometry: geometry, margins: margins)
        let (view, page) = Self.foliatePage(layout, readerWidth: Double(geometry.size.width))
        #expect(view == view.rounded())
        #expect(page == page.rounded())
    }

    @Test(arguments: ReaderMargins.allCases)
    func sidewaysPageIsWholePoints(margins: ReaderMargins) {
        let layout = ReaderLayout(posture: .open, geometry: Self.sideways, margins: margins)
        let (view, page) = Self.foliatePage(layout, readerWidth: 669)
        #expect(view == view.rounded())
        #expect(page == page.rounded())
    }

    // 823.66 pt before: Narrow's view and gap were shares of the screen.
    @Test func narrowSpreadIsAWholePageWithTheTextAtTheEdges() throws {
        let layout = ReaderLayout(posture: .open, geometry: Self.unfoldedScreen(), margins: .narrow)
        #expect(layout.leftInset == 43)
        #expect(layout.rightInset == 43)
        #expect(Self.foliatePage(layout, readerWidth: 951).page == 824)
        let columns = try #require(layout.textColumns(inReaderWidth: 951))
        #expect(Self.near(columns[0].lowerBound, 84, within: 0.01))
        #expect(Self.near(columns[0].upperBound, 455, within: 0.01))
        #expect(Self.near(columns[1].lowerBound, 496, within: 0.01))
        #expect(Self.near(columns[1].upperBound, 867, within: 0.01))
    }

    // MARK: The progress bar (Adam, 2026-11-04: as wide as a panel)

    @Test(arguments: ReaderMargins.allCases)
    func barIsAPanelsWidthFolded(margins: ReaderMargins) {
        let layout = ReaderLayout(posture: .closed, geometry: Self.foldedScreen, margins: margins)
        #expect(layout.barSpans(in: Self.foldedScreen, bookMode: false) == [12...370])
        // Just above the home indicator.
        #expect(ReaderLayout.barBottom(in: Self.foldedScreen) == 644)
    }

    // Its right edge is a panel's; its left edge mirrors it across the screen.
    @Test(arguments: ReaderMargins.allCases)
    func barSpansTheSpreadFlat(margins: ReaderMargins) {
        let layout = ReaderLayout(posture: .open, geometry: Self.unfoldedScreen(), margins: margins)
        #expect(layout.barSpans(in: Self.unfoldedScreen(), bookMode: false) == [96...855])
        #expect(ReaderLayout.barBottom(in: Self.unfoldedScreen()) == 635)
    }

    // Half open, a piece under each page and nothing on the hinge. The right
    // one is exactly a panel's width.
    @Test(arguments: ReaderMargins.allCases)
    func barSplitsUnderEachPageInBookMode(margins: ReaderMargins) {
        let geometry = Self.unfoldedScreen(active: true)
        let layout = ReaderLayout(posture: .halfOpen, geometry: geometry, margins: margins)
        #expect(layout.barSpans(in: geometry, bookMode: true) == [96...443.5, 507.5...855])
    }

    @Test func barKeepsToTheSafeAreaWithoutAHinge() {
        let geometry = ReaderGeometry(size: CGSize(width: 1024, height: 768), safeArea: ReaderInsets(top: 0, left: 0, bottom: 0, right: 84))
        let layout = ReaderLayout(posture: .noHinge, geometry: geometry)
        #expect(layout.barSpans(in: geometry, bookMode: false) == [12...928])
        #expect(ReaderLayout.barBottom(in: geometry) == 756)
    }
}
