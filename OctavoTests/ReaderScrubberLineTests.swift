import Foundation
import Testing
@testable import Octavo

/// The scrubber's line (decision 35): dots at chapters, a zoom around the
/// finger with a dot per page, and a catch at chapter starts when zoomed.
struct ReaderScrubberLineTests {
    /// Moby-Dick folded: 974 pages over 259 pt.
    private let moby = ReaderScrubberLine(chapters: [0.1, 0.4, 0.402, 0.5], total: 974, travel: 259)

    // MARK: Zooming

    @Test func zoomingGivesEachPageEightPoints() throws {
        let window = try #require(moby.zoomed(around: 0.5, in: ReaderScrubberLine.wholeBook))
        let width = window.upperBound - window.lowerBound
        #expect(abs(width * 974 * ReaderScrubberLine.pointsPerPage / 259 - 1) < 1e-9)
    }

    /// The knob stays under the finger: the same share along the line.
    @Test(arguments: [0.2, 0.5, 0.8])
    func theKnobStaysWhereItIsOnTheLine(value: Double) throws {
        let window = try #require(moby.zoomed(around: value, in: ReaderScrubberLine.wholeBook))
        let ratio = (value - window.lowerBound) / (window.upperBound - window.lowerBound)
        #expect(abs(ratio - value) < 1e-9)
    }

    @Test(arguments: [0.0, 0.001, 0.999, 1.0])
    func aZoomStopsAtTheBooksEnds(value: Double) throws {
        let window = try #require(moby.zoomed(around: value, in: 0.0...0.03))
        #expect(window.lowerBound >= 0)
        #expect(window.upperBound <= 1 + 1e-12)
    }

    @Test func aShortBookHasNoZoom() {
        let line = ReaderScrubberLine(chapters: [], total: 20, travel: 259)
        #expect(line.zoomed(around: 0.5, in: ReaderScrubberLine.wholeBook) == nil)
    }

    @Test func aBookWithoutPageNumbersHasNoZoom() {
        let line = ReaderScrubberLine(chapters: [], total: nil, travel: 259)
        #expect(line.zoomed(around: 0.5, in: ReaderScrubberLine.wholeBook) == nil)
        #expect(line.pageDots(in: 0.4...0.5).isEmpty)
    }

    // MARK: Dots

    /// 0.402 is half a point past 0.4 at this width.
    @Test func chaptersTooCloseShareADot() {
        #expect(moby.chapterDots == [0.1, 0.4, 0.5])
    }

    /// Entries in the same section start at the same place until they're
    /// placed properly (`refineContents`).
    @Test func chaptersStartingTogetherAreOneChapter() {
        let line = ReaderScrubberLine(chapters: [0.5, 0.1, 0.5], total: 100, travel: 259)
        #expect(line.chapters == [0.1, 0.5])
    }

    @Test func aDotForEachPageInTheWindow() {
        let line = ReaderScrubberLine(chapters: [], total: 100, travel: 259)
        #expect(line.pageDots(in: 0.095...0.135).map { Int(($0 * 100).rounded()) } == [10, 11, 12, 13])
    }

    @Test func barsAreTheChaptersInTheWindow() {
        #expect(moby.chapterBars(in: 0.39...0.45) == [0.4, 0.402])
    }

    // MARK: The catch

    @Test func theKnobCatchesWithinThreePoints() {
        // A 33-page window over 259 pt: a point is about 0.00013.
        let window = 0.48...0.5135
        let perPoint = (window.upperBound - window.lowerBound) / 259
        #expect(moby.caughtChapter(near: 0.5 + 2.9 * perPoint, in: window) == 0.5)
        #expect(moby.caughtChapter(near: 0.5 - 2.9 * perPoint, in: window) == 0.5)
        #expect(moby.caughtChapter(near: 0.5 + 3.1 * perPoint, in: window) == nil)
    }

    @Test func theNearestChapterCatches() {
        let line = ReaderScrubberLine(chapters: [0.5, 0.5002], total: 974, travel: 259)
        #expect(line.caughtChapter(near: 0.50015, in: 0.48...0.5135) == 0.5002)
    }

    @Test func aChapterOutsideTheWindowDoesntCatch() {
        #expect(moby.caughtChapter(near: 0.4, in: 0.41...0.44) == nil)
    }

    // MARK: Passing chapters

    @Test func theChapterAtAPlace() {
        #expect(moby.chapterIndex(at: 0.05) == nil)
        #expect(moby.chapterIndex(at: 0.1) == 0)
        #expect(moby.chapterIndex(at: 0.45) == 2)
        #expect(moby.chapterIndex(at: 0.9) == 3)
    }

    // MARK: Sliding at the ends

    @Test func theLineSlidesOnlyAtItsEnds() throws {
        #expect(ReaderScrubberLine.slid(0.4...0.5, knobAt: 0.5, elapsed: 0.1) == nil)
        let right = try #require(ReaderScrubberLine.slid(0.4...0.5, knobAt: 0.95, elapsed: 0.1))
        #expect(right.lowerBound > 0.4)
        let left = try #require(ReaderScrubberLine.slid(0.4...0.5, knobAt: 0.05, elapsed: 0.1))
        #expect(left.lowerBound < 0.4)
    }

    @Test func theLineKeepsItsLengthAndStopsAtTheBooksEnds() throws {
        let slid = try #require(ReaderScrubberLine.slid(0.89...0.99, knobAt: 0.95, elapsed: 1))
        #expect(abs(slid.upperBound - 1) < 1e-12)
        #expect(abs(slid.upperBound - slid.lowerBound - 0.1) < 1e-9)
        #expect(ReaderScrubberLine.slid(0.0...0.1, knobAt: 0.05, elapsed: 1) == nil)
    }

    // MARK: A quick move

    @Test func aFastMoveIsQuick() {
        var speed = ReaderScrubberSpeed()
        let first = speed.moved(to: 100, at: 0)
        let second = speed.moved(to: 120, at: 0.03)
        #expect(!first)
        #expect(second)
    }

    @Test func aSlowMoveIsNot() {
        var speed = ReaderScrubberSpeed()
        for step in 0..<20 {
            let quick = speed.moved(to: 100 + Double(step) * 2, at: Double(step) * 0.15)
            #expect(!quick)
        }
    }

    /// Touches arriving together aren't a fast finger.
    @Test func aBunchedPairIsNot() {
        var speed = ReaderScrubberSpeed()
        _ = speed.moved(to: 100, at: 1)
        let quick = speed.moved(to: 102, at: 1.001)
        #expect(!quick)
    }

    /// A move after a pause reads from the move, not the pause.
    @Test func aPauseDoesntHideAQuickMove() {
        var speed = ReaderScrubberSpeed()
        _ = speed.moved(to: 100, at: 0)
        let afterPause = speed.moved(to: 120, at: 0.5)
        let quick = speed.moved(to: 160, at: 0.56)
        #expect(!afterPause)
        #expect(quick)
    }
}
