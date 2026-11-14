import Foundation
import OctavoKit
import Testing

struct ReadingPaceTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func page(_ characters: Int, seconds: Double) -> ReadingSpan {
        ReadingSpan(start: start, end: start.addingTimeInterval(seconds), characters: characters)
    }

    /// `count` pages of 1,000 characters at `perSecond`.
    private func read(_ pace: inout ReadingPace, book: String, count: Int, perSecond: Double) {
        for _ in 0..<count { pace.record(page(1000, seconds: 1000 / perSecond), book: book) }
    }

    @Test func noPaceUntilTenPagesCount() {
        var pace = ReadingPace()
        read(&pace, book: "a", count: 9, perSecond: 20)
        #expect(!pace.hasPace())
        #expect(pace.speed(forBook: "a") == nil)
        #expect(pace.seconds(toRead: 1000, book: "a") == nil)
        read(&pace, book: "a", count: 1, perSecond: 20)
        #expect(pace.hasPace())
        #expect(pace.speed(forBook: "a") == 20)
    }

    @Test func leafingPausesAndShortPagesDontCount() {
        var pace = ReadingPace()
        #expect(pace.record(page(1000, seconds: 2), book: "a") == .leafing)
        // Under a quarter of the starting speed's 40 s.
        #expect(pace.record(page(1000, seconds: 9), book: "a") == .leafing)
        #expect(pace.record(page(1000, seconds: 121), book: "a") == .pause)
        #expect(pace.record(page(150, seconds: 30), book: "a") == .tooShort)
        #expect(pace.overall.pages == 0)
        #expect(pace.record(page(1000, seconds: 40), book: "a") == .counted)
        #expect(pace.overall.pages == 1)
    }

    @Test func aDenseSpreadIsntAPause() {
        var pace = ReadingPace()
        read(&pace, book: "a", count: 10, perSecond: 10)
        // 3,000 characters at 10 a second is 5 minutes, past the 2 minutes.
        #expect(pace.judge(page(3000, seconds: 300), book: "a") == .counted)
        #expect(pace.judge(page(3000, seconds: 901), book: "a") == .pause)
    }

    @Test func aNewBookStartsFromTheOverallSpeedAndMovesToItsOwn() throws {
        var pace = ReadingPace()
        read(&pace, book: "a", count: 40, perSecond: 20)
        #expect(pace.speed(forBook: "b") == 20)
        read(&pace, book: "b", count: 20, perSecond: 10)
        let b = try #require(pace.speed(forBook: "b"))
        #expect(b < 20 && b > 10)
        read(&pace, book: "b", count: 200, perSecond: 10)
        #expect(try #require(pace.speed(forBook: "b")) < 11)
    }

    @Test func oldPagesFade() throws {
        var pace = ReadingPace()
        read(&pace, book: "a", count: 200, perSecond: 20)
        read(&pace, book: "a", count: 400, perSecond: 10)
        #expect(pace.overall.pages <= 200)
        let speed = try #require(pace.overall.perSecond)
        #expect(speed > 10 && speed < 11.5)
    }

    @Test func removesBooks() {
        var pace = ReadingPace()
        read(&pace, book: "server1/a", count: 1, perSecond: 20)
        read(&pace, book: "files/b", count: 1, perSecond: 20)
        pace.removeBooks { $0.hasPrefix("server1/") }
        #expect(Array(pace.books.keys) == ["files/b"])
    }

    @Test func roundsTimeLeft() {
        #expect(ReadingTimeLeft(seconds: 20) == .underAMinute)
        #expect(ReadingTimeLeft(seconds: 61) == .minutes(1))
        #expect(ReadingTimeLeft(seconds: 8 * 60 + 40) == .minutes(9))
        #expect(ReadingTimeLeft(seconds: 59 * 60 + 40) == .hours(1, minutes: 0))
        #expect(ReadingTimeLeft(seconds: (3 * 60 + 38) * 60) == .hours(3, minutes: 40))
        #expect(ReadingTimeLeft(seconds: (9 * 60 + 54) * 60) == .hours(9, minutes: 50))
        #expect(ReadingTimeLeft(seconds: (9 * 60 + 56) * 60) == .hours(10, minutes: 0))
        #expect(ReadingTimeLeft(seconds: (12 * 60 + 20) * 60) == .hours(12, minutes: 0))
    }
}

struct BookTextMapTests {
    // Three sections: 1,000 characters in the first 0.5 of the book, a
    // section foliate leaves out, then 3,000 in the rest.
    private let map = BookTextMap(sections: [1000, 0, 3000], starts: [0, 0.5, 0.5, 1])!

    @Test func needsAStartForEachSection() {
        #expect(BookTextMap(sections: [1, 2], starts: [0, 1]) == nil)
        #expect(BookTextMap(sections: [], starts: [0]) == nil)
    }

    @Test func countsCharactersBeforeAPlace() {
        #expect(map.total == 4000)
        #expect(map.characters(before: 0) == 0)
        #expect(map.characters(before: 0.25) == 500)
        #expect(map.characters(before: 0.5) == 1000)
        #expect(map.characters(before: 0.75) == 2500)
        #expect(map.characters(before: 1) == 4000)
        #expect(map.characters(from: 0.25, to: 0.75) == 2000)
        #expect(map.characters(from: 0.75, to: 0.25) == 0)
    }

    @Test func anUnreadSectionLeavesItsRestUnknown() {
        let map = BookTextMap(sections: [1000, nil], starts: [0, 0.5, 1])!
        #expect(map.total == nil)
        #expect(map.characters(before: 0.25) == 500)
        #expect(map.characters(before: 0.75) == nil)
    }
}
