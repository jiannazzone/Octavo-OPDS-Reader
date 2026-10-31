import CoreGraphics
import Foundation
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
        #expect(ReaderLayout(posture: .closed, geometry: Self.folded) == .single)
    }

    // While closing, the region briefly reports for the inner display.
    @Test func closedIgnoresALeftoverFold() {
        #expect(ReaderLayout(posture: .closed, geometry: Self.unfolded(active: true)) == .single)
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
        #expect(ReaderLayout(posture: .halfOpen, geometry: geometry) == .single)
    }

    @Test func foldTooCloseToAnEdgeIsOnePage() {
        let nearEdge = CGRect(x: 100, y: -176, width: 40, height: 669)
        #expect(ReaderLayout(posture: .open, geometry: Self.unfolded(active: true, fold: nearEdge)) == .single)
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
        #expect(ReaderLayout(posture: .open, geometry: ReaderGeometry(size: CGSize(width: 466, height: 510))) == .single)
    }

    @Test func noHingeLeavesItToFoliate() {
        #expect(ReaderLayout(posture: .noHinge, geometry: ReaderGeometry(size: CGSize(width: 1024, height: 768))) == .automatic)
        #expect(ReaderLayout(posture: .noHinge, geometry: nil) == .automatic)
    }

    @Test func noHingeStillFollowsAnActiveFold() {
        #expect(ReaderLayout(posture: .noHinge, geometry: Self.unfolded(active: true)).columns == 2)
        #expect(ReaderLayout(posture: .noHinge, geometry: Self.unfolded(active: false)) == .automatic)
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
