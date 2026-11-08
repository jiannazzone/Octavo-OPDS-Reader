import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Octavo

/// Page turns (decision 27): Page Turn and Reduce Motion, a finger's turn,
/// the pictures each motion needs, and the bridge's messages.
struct ReaderPageTurnTests {
    // MARK: Page Turn

    /// Adam, 2026-11-07: one page and a spread alike.
    @Test func automaticCurls() {
        #expect(ReaderPageTurn.automatic.motion(spread: false, reduceMotion: false) == .curl)
        #expect(ReaderPageTurn.automatic.motion(spread: true, reduceMotion: false) == .curl)
    }

    @Test(arguments: [false, true])
    func automaticFadesWithReduceMotion(spread: Bool) {
        #expect(ReaderPageTurn.automatic.motion(spread: spread, reduceMotion: true) == .fade)
    }

    /// Any choice but Automatic applies in every posture, Reduce Motion or not.
    @Test(arguments: [
        (ReaderPageTurn.slide, ReaderTurnMotion.slide),
        (.flip, .flip),
        (.curl, .curl),
        (.fade, .fade),
        (.none, .none),
    ])
    func aChoiceByHandIsKept(style: ReaderPageTurn, motion: ReaderTurnMotion) {
        for spread in [false, true] {
            for reduceMotion in [false, true] {
                #expect(style.motion(spread: spread, reduceMotion: reduceMotion) == motion)
            }
        }
    }

    @Test func onlyNoneLeavesTheTurnsToTheBridge() {
        #expect(ReaderPageTurn.allCases.filter { !$0.isAnimated } == [.none])
    }

    @Test func isSavedByName() {
        #expect(ReaderPageTurn.key == "reader.pageTurn")
        #expect(ReaderPageTurn.standard == .automatic)
        #expect(ReaderPageTurn.allCases.map(\.rawValue) == ["automatic", "slide", "flip", "curl", "fade", "none"])
    }

    @Test func menuNames() {
        #expect(ReaderPageTurn.allCases.map(\.name) == ["Automatic", "Slide", "Flip", "Curl", "Fade", "None"])
    }

    /// Where pages curl, UIKit's pan follows the finger instead of
    /// `ReaderSwipeRecognizer`. Curl picked by hand keeps curling with Reduce
    /// Motion; Automatic fades.
    @Test func whereUIKitTakesTheFinger() {
        #expect(ReaderPageTurn.automatic.curls(reduceMotion: false))
        #expect(!ReaderPageTurn.automatic.curls(reduceMotion: true))
        #expect(ReaderPageTurn.curl.curls(reduceMotion: true))
        for style in [ReaderPageTurn.slide, .flip, .fade, .none] {
            #expect(!style.curls(reduceMotion: false))
        }
    }

    @Test func speeds() {
        #expect(ReaderTurnMotion.slide.duration == 0.3)
        #expect(ReaderTurnMotion.flip.duration == 0.5)
        #expect(ReaderTurnMotion.fade.duration == 0.15)
        #expect(ReaderTurnMotion.none.duration == 0)
    }

    // MARK: A finger's turn

    @Test func aSlideFollowsTheFingerPointForPoint() {
        #expect(ReaderTurnDrag.progress(dx: -100, side: .right, motion: .slide, pageWidth: 400) == 0.25)
        #expect(ReaderTurnDrag.progress(dx: 100, side: .left, motion: .slide, pageWidth: 400) == 0.25)
        #expect(ReaderTurnDrag.progress(dx: -900, side: .right, motion: .slide, pageWidth: 400) == 1)
    }

    /// Back past where it started holds the page flat; it doesn't turn the
    /// other way.
    @Test(arguments: [ReaderTurnMotion.slide, .flip, .fade])
    func movingTheOtherWayHoldsThePageFlat(motion: ReaderTurnMotion) {
        #expect(ReaderTurnDrag.progress(dx: 40, side: .right, motion: motion, pageWidth: 400) == 0)
        #expect(ReaderTurnDrag.progress(dx: -40, side: .left, motion: motion, pageWidth: 400) == 0)
    }

    /// The turning page's edge stays under the finger: halfway (standing
    /// up) when the finger has crossed one page, flat on the other side
    /// after two.
    @Test func aFlipKeepsThePagesEdgeUnderTheFinger() {
        let width = 476.0
        #expect(abs(ReaderTurnDrag.progress(dx: -width, side: .right, motion: .flip, pageWidth: width) - 0.5) < 1e-9)
        #expect(ReaderTurnDrag.progress(dx: -2 * width, side: .right, motion: .flip, pageWidth: width) == 1)
        #expect(ReaderTurnDrag.progress(dx: -3 * width, side: .right, motion: .flip, pageWidth: width) == 1)
        for dx in stride(from: 10.0, through: 2 * width, by: 37) {
            let progress = ReaderTurnDrag.progress(dx: dx, side: .left, motion: .flip, pageWidth: width)
            let edgeMoved = width * (1 - cos(.pi * progress))
            #expect(abs(edgeMoved - dx) < 1e-6)
        }
    }

    @Test func noWidthNoTurn() {
        #expect(ReaderTurnDrag.progress(dx: -100, side: .right, motion: .slide, pageWidth: 0) == 0)
    }

    @Test func pastHalfwayFinishesAndBeforeFallsBack() {
        #expect(ReaderTurnDrag.finishes(progress: 0.5, velocity: 0, side: .right))
        #expect(ReaderTurnDrag.finishes(progress: 0.8, velocity: -0.1, side: .right))
        #expect(!ReaderTurnDrag.finishes(progress: 0.49, velocity: 0, side: .right))
        #expect(!ReaderTurnDrag.finishes(progress: 0.2, velocity: 0.1, side: .left))
    }

    /// A flick goes the way it points, however far the page has gone.
    @Test func aFlickDecides() {
        #expect(ReaderTurnDrag.finishes(progress: 0.1, velocity: -0.5, side: .right))
        #expect(!ReaderTurnDrag.finishes(progress: 0.9, velocity: 0.5, side: .right))
        #expect(ReaderTurnDrag.finishes(progress: 0.1, velocity: 0.5, side: .left))
        #expect(!ReaderTurnDrag.finishes(progress: 0.9, velocity: -0.5, side: .left))
    }

    @Test func theRestPlaysAtTheTurnsPaceButNeverJumps() {
        #expect(ReaderTurnDrag.remainingDuration(from: 0.5, to: 1, motion: .flip) == 0.25)
        #expect(ReaderTurnDrag.remainingDuration(from: 0.6, to: 0, motion: .slide) == 0.3 * 0.6)
        #expect(ReaderTurnDrag.remainingDuration(from: 0.98, to: 1, motion: .flip) == 0.12)
        #expect(ReaderTurnDrag.remainingDuration(from: 0.98, to: 1, motion: .fade) == 0.12)
        let ramp = ReaderTurnRamp(from: 0.25, to: 1, start: 10, duration: 0.2, curve: .easeOut)
        #expect(ramp.end == 10.2)
        #expect(ramp.progress(at: 9) == 0.25)
        #expect(ramp.progress(at: 10) == 0.25)
        #expect(ramp.progress(at: 10.1) > 0.25 + 0.75 / 2)
        #expect(ramp.progress(at: 10.2) == 1)
        #expect(ramp.progress(at: 11) == 1)
        let fallingBack = ReaderTurnRamp(from: 0.4, to: 0, start: 0, duration: 0.12, curve: .easeOut)
        #expect(fallingBack.progress(at: 0.06) < 0.2)
        #expect(fallingBack.progress(at: 0.12) == 0)
    }

    @Test func sides() {
        #expect(ReaderTurnSide.left.opposite == .right)
        #expect(ReaderTurnSide.right.opposite == .left)
    }

    // MARK: Pictures

    static let spread = CGSize(width: 951, height: 669)

    @Test func aSlideTakesBothPagesWhole() {
        let regions = ReaderTurn.regions(motion: .slide, side: .right, size: Self.spread, spine: nil)
        #expect(regions.old == .whole)
        #expect(regions.new == .whole)
    }

    /// The web view already shows the new page under a fade.
    @Test func aFadeTakesOnlyTheOldPage() {
        let regions = ReaderTurn.regions(motion: .fade, side: .left, size: Self.spread, spine: nil)
        #expect(regions.old == .whole)
        #expect(regions.new.isEmpty)
    }

    /// The new page is needed only on the back of the turning page: the
    /// half it lands on.
    @Test func aSpreadsFlipTakesTheNewPageItLandsAs() {
        let forward = ReaderTurn.regions(motion: .flip, side: .right, size: Self.spread, spine: 475.5)
        #expect(forward.old == [.left, .right])
        #expect(forward.new == .left)
        let back = ReaderTurn.regions(motion: .flip, side: .left, size: Self.spread, spine: 475.5)
        #expect(back.old == [.left, .right])
        #expect(back.new == .right)
    }

    /// One page flips about its left edge: forward it uncovers the new page
    /// (the web view's); back, the page before comes over it.
    @Test func onePagesFlip() {
        let page = CGSize(width: 466, height: 678)
        let forward = ReaderTurn.regions(motion: .flip, side: .right, size: page, spine: nil)
        #expect(forward.old == .whole)
        #expect(forward.new.isEmpty)
        let back = ReaderTurn.regions(motion: .flip, side: .left, size: page, spine: nil)
        #expect(back.new == .whole)
    }

    /// A curl takes what a flip takes: the page it uncovers is the web view,
    /// clear under UIKit's curl.
    @Test(arguments: [ReaderTurnSide.left, .right], [CGSize(width: 466, height: 678), Self.spread])
    func aCurlTakesWhatAFlipTakes(side: ReaderTurnSide, size: CGSize) {
        let spine: Double? = size == Self.spread ? 475.5 : nil
        let curl = ReaderTurn.regions(motion: .curl, side: side, size: size, spine: spine)
        let flip = ReaderTurn.regions(motion: .flip, side: side, size: size, spine: spine)
        #expect(curl.old == flip.old)
        #expect(curl.new == flip.new)
    }

    @Test func halvesMeetAtTheSpine() {
        let left = ReaderTurn.half(.left, of: Self.spread, spine: 475.5)
        let right = ReaderTurn.half(.right, of: Self.spread, spine: 475.5)
        #expect(left == CGRect(x: 0, y: 0, width: 475.5, height: 669))
        #expect(right == CGRect(x: 475.5, y: 0, width: 475.5, height: 669))
    }

    // MARK: The bridge's messages

    @Test func decodesATurnRequest() throws {
        #expect(try ReaderMessage.decode(#"{"type":"turn","side":"right"}"#) == .turn(side: .right))
        #expect(try ReaderMessage.decode(#"{"type":"turn","side":"left"}"#) == .turn(side: .left))
    }

    @Test func refusesATurnWithoutASide() {
        #expect(throws: (any Error).self) { try ReaderMessage.decode(#"{"type":"turn","side":"up"}"#) }
        #expect(throws: (any Error).self) { try ReaderMessage.decode(#"{"type":"turn"}"#) }
    }

    @Test func decodesSelection() throws {
        #expect(try ReaderMessage.decode(#"{"type":"selection","active":true}"#) == .selection(active: true))
        #expect(try ReaderMessage.decode(#"{"type":"selection","active":false}"#) == .selection(active: false))
        #expect(try ReaderMessage.decode(#"{"type":"selection"}"#) == .selection(active: false))
    }

    /// The relocation `turn` returns, as JSON, for the new page's footer.
    @Test func decodesTheTurnsRelocation() throws {
        let json = #"{"cfi":"epubcfi(/6/50!/4/2,/2/1:0,/4/1:12)","fraction":0.36,"tocLabel":"XXV","sectionIndex":24,"location":{"current":198,"next":200,"total":547}}"#
        let relocation = try JSONDecoder().decode(ReaderMessage.Relocation.self, from: Data(json.utf8))
        let place = ReaderPlace(chapter: relocation.tocLabel, location: relocation.location, fraction: relocation.fraction ?? 0)
        #expect(place.chapter == "XXV")
        #expect(place.first == 199)
        #expect(place.last == 201)
        #expect(place.total == 547)
    }
}
