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

    @Test func spreadKeepsFoliatesSpacingWhenTheFoldIsNarrower() {
        let layout = ReaderLayout(posture: .open, geometry: Self.unfolded(active: false))
        // 40 of 951 is 4.3%, under foliate's 7%.
        #expect(layout.gapPercent == ReaderLayout.defaultGapPercent)
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
        #expect(Self.near(text.lowerBound, 26.7))
        #expect(Self.near(text.upperBound, 355.3))
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
        #expect(Self.near(columns[0].lowerBound, 138.8))
        #expect(Self.near(columns[0].upperBound, 448.1))
        #expect(Self.near(columns[1].lowerBound, 502.9))
        #expect(Self.near(columns[1].upperBound, 812.2))
        #expect(columns[0].upperBound <= 455.5)
        #expect(columns[1].lowerBound >= 495.5)
    }

    @Test(arguments: [(ReaderMargins.narrow, 18.4), (.medium, 26.7), (.wide, 38.2)])
    func foldedMargins(margins: ReaderMargins, margin: Double) throws {
        let layout = ReaderLayout(posture: .closed, geometry: Self.foldedScreen, margins: margins)
        let text = try #require(layout.textColumns(inReaderWidth: 466)?.first)
        #expect(Self.near(text.lowerBound, margin, within: 0.1))
        if margins == .narrow {
            // The text reaches the column's edge; the margin lies under it.
            #expect(Self.near(text.upperBound, 382, within: 0.1))
        } else {
            #expect(Self.near(text.upperBound, 382 - margin, within: 0.1))
        }
    }

    // Narrow's gap rounds up to 4.7%: a 40.6 pt gutter, just over the hinge.
    @Test(arguments: [(ReaderMargins.narrow, 40.6), (.medium, 54.8), (.wide, 78.3)])
    func unfoldedMarginsAndGutter(margins: ReaderMargins, gutter: Double) throws {
        let layout = ReaderLayout(posture: .open, geometry: Self.unfoldedScreen(), margins: margins)
        let columns = try #require(layout.textColumns(inReaderWidth: 951))
        #expect(Self.near(columns[1].lowerBound - columns[0].upperBound, gutter))
        // Never narrower than the hinge.
        #expect(columns[0].upperBound <= 455.5)
        #expect(columns[1].lowerBound >= 495.5)
        // Still centred on the hinge.
        #expect(Self.near((columns[0].upperBound + columns[1].lowerBound) / 2, 475.5, within: 0.01))
        if margins == .narrow {
            #expect(Self.near(columns[0].lowerBound, 84))
            #expect(Self.near(columns[1].upperBound, 867))
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
        #expect(arguments["gapPercent"] as? Double == 7)
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
        #expect(spread["gapPercent"] as? Double == 7)
        #expect(spread["fold"] as? [Double] == [455.5, 495.5])
    }
}
