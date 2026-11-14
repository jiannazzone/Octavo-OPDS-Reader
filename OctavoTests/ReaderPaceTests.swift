import Foundation
import OctavoKit
import Testing
@testable import Octavo

struct ReaderPaceClockTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func aTurnForwardHandsBackThePageLeft() {
        var clock = ReaderPaceClock()
        #expect(clock.arrived(fraction: 0.1, characters: 900, turnedForward: false, at: start) == nil)
        let span = clock.arrived(fraction: 0.11, characters: 1200, turnedForward: true, at: start + 40)
        #expect(span == ReadingSpan(start: start, end: start + 40, characters: 900))
    }

    @Test func anythingElseStartsTheClockAgain() {
        var clock = ReaderPaceClock()
        _ = clock.arrived(fraction: 0.1, characters: 900, turnedForward: false, at: start)
        // A jump on…
        #expect(clock.arrived(fraction: 0.5, characters: 800, turnedForward: false, at: start + 30) == nil)
        // …then a turn back, which isn't reading on.
        #expect(clock.arrived(fraction: 0.49, characters: 700, turnedForward: true, at: start + 60) == nil)
        // The turn after counts the page from when it came.
        #expect(clock.arrived(fraction: 0.5, characters: 800, turnedForward: true, at: start + 100)?.seconds == 40)
    }

    @Test func timeAwayIsntReading() {
        var clock = ReaderPaceClock()
        _ = clock.arrived(fraction: 0.1, characters: 900, turnedForward: false, at: start)
        clock.stop()
        clock.restart(at: start + 600)
        #expect(clock.arrived(fraction: 0.11, characters: 900, turnedForward: true, at: start + 640)?.seconds == 40)
    }
}

struct ReaderFooterReadoutTests {
    @Test func cyclesThroughWhatCanShow() {
        #expect(ReaderFooterReadout.chapterTime.next(hasTime: true, hasPages: true) == .bookTime)
        #expect(ReaderFooterReadout.bookTime.next(hasTime: true, hasPages: true) == .page)
        #expect(ReaderFooterReadout.page.next(hasTime: true, hasPages: true) == .percent)
        #expect(ReaderFooterReadout.percent.next(hasTime: true, hasPages: true) == .chapterTime)
        // Before a pace, page and percent alone.
        #expect(ReaderFooterReadout.percent.next(hasTime: false, hasPages: true) == .page)
        #expect(ReaderFooterReadout.page.next(hasTime: false, hasPages: true) == .percent)
        #expect(ReaderFooterReadout.percent.next(hasTime: false, hasPages: false) == .percent)
    }

    @Test func timeWaitsForAPaceOnPage() {
        #expect(ReaderFooterReadout.chapterTime.shown(hasTime: false, hasPages: true) == .page)
        #expect(ReaderFooterReadout.bookTime.shown(hasTime: false, hasPages: false) == .percent)
        #expect(ReaderFooterReadout.chapterTime.shown(hasTime: true, hasPages: true) == .chapterTime)
    }

    @Test func timeLeftRunsToTheNextEntry() throws {
        let map = try #require(BookTextMap(sections: [6000, 6000], starts: [0, 0.5, 1]))
        let toc = [ReaderMessage.TOCEntry(label: "One", fraction: 0), ReaderMessage.TOCEntry(label: "Two", fraction: 0.5)]
        let time = ReaderTimeLeft(map: map, toc: toc, speed: 10)
        #expect(time.chapter(from: 0.25) == 300)
        #expect(time.book(from: 0.25) == 900)
        #expect(time.chapter(from: 0.75) == 300)
    }

    @Test func wording() {
        #expect(ReaderTimeLeftText.short(.minutes(12), .chapter) == "12 min left in chapter")
        #expect(ReaderTimeLeftText.short(.hours(3, minutes: 40), .book) == "3 h 40 min left in book")
        #expect(ReaderTimeLeftText.short(.hours(12, minutes: 0), .book) == "12 h left in book")
        #expect(ReaderTimeLeftText.short(.underAMinute, .chapter) == "Under 1 min left in chapter")
        #expect(ReaderTimeLeftText.spoken(.hours(3, minutes: 40), .book) == "3 hours, 40 minutes left in book")
    }
}
