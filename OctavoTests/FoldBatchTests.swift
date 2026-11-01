import Foundation
import Testing
@testable import Octavo

/// When a fold's batched inputs get laid out.
struct FoldBatchTests {
    let start = ContinuousClock.now
    let timing = FoldBatch.Timing(quiet: .milliseconds(120), maxWait: .milliseconds(2000))

    func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    @Test func waitsForThePageToResize() {
        var batch = FoldBatch(startedAt: start)
        // The hinge, the reader's size and the fold region, but no resize yet.
        batch.input(at: at(10))
        batch.input(at: at(150))
        #expect(batch.deadline(timing) == at(2000))
    }

    @Test func laysOutOnceQuietAfterTheResize() {
        var batch = FoldBatch(startedAt: start)
        batch.input(at: at(150))
        batch.pageResized(at: at(210))
        #expect(batch.deadline(timing) == at(330))
        // A late fold region moves it on.
        batch.input(at: at(300))
        #expect(batch.deadline(timing) == at(420))
    }

    @Test func neverWaitsLongerThanMaxWait() {
        var batch = FoldBatch(startedAt: start)
        batch.pageResized(at: at(1950))
        #expect(batch.deadline(timing) == at(2000))
    }

    @Test func anInputFromBeforeTheLatestDoesntMoveTheDeadlineBack() {
        var batch = FoldBatch(startedAt: start)
        batch.pageResized(at: at(300))
        batch.input(at: at(100))
        #expect(batch.deadline(timing) == at(420))
    }

    @Test func foldingBackWaitsForTheNextResize() {
        var batch = FoldBatch(startedAt: start)
        batch.pageResized(at: at(200))
        batch.restart(at: at(250))
        #expect(!batch.pageResized)
        #expect(batch.deadline(timing) == at(2250))
        batch.pageResized(at: at(500))
        #expect(batch.deadline(timing) == at(620))
    }

    @Test(arguments: [
        (ReaderPosture.closed, true), (.halfOpen, false), (.open, false), (.noHinge, false),
    ])
    func onlyClosedIsFolded(posture: ReaderPosture, folded: Bool) {
        #expect(posture.isFolded == folded)
    }
}
