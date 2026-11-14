import Foundation

/// A page read: how long it stayed on screen and the characters on it. What
/// the reader hands `ReadingPace`, and what reading sessions can later be
/// built from (#121).
public nonisolated struct ReadingSpan: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var characters: Int

    public init(start: Date, end: Date, characters: Int) {
        self.start = start
        self.end = end
        self.characters = characters
    }

    public var seconds: Double { end.timeIntervalSince(start) }
}

/// What counts as reading. Starting values, to be set on a real Duo (#124).
public nonisolated struct ReadingPaceRules: Equatable, Sendable {
    /// A page this quick was leafed past, whatever it holds.
    public var leafingSeconds = 3.0
    /// …or one read in under this share of the time the speed gives it.
    public var leafingShare = 0.25
    /// A page on screen this long had a break in it…
    public var breakSeconds = 120.0
    /// …unless the speed gives it longer than this share.
    public var breakShare = 3.0
    /// A page with less text (a title, a picture) says little about speed.
    public var minimumCharacters = 200
    /// Pages counted before there's a pace.
    public var pagesForPace = 10
    /// A book starts as this many pages at the overall speed.
    public var bookPrior = 20.0
    /// Pages a speed remembers; older ones fade.
    public var memory = 200.0
    /// The speed a page is judged by before there's a pace: brisk, so a
    /// fast reader isn't taken for leafing. 1,500 characters a minute.
    public var startingSpeed = 25.0

    public init() {}

    public static let standard = ReadingPaceRules()
}

/// Characters read and the time it took, over the pages that counted.
public nonisolated struct ReadingSpeed: Codable, Equatable, Sendable {
    public var characters: Double = 0
    public var seconds: Double = 0
    /// Pages counted, capped at `ReadingPaceRules.memory`.
    public var pages: Double = 0

    public init(characters: Double = 0, seconds: Double = 0, pages: Double = 0) {
        self.characters = characters
        self.seconds = seconds
        self.pages = pages
    }

    /// Characters a second, or `nil` with nothing counted.
    public var perSecond: Double? {
        seconds > 0 && characters > 0 ? characters / seconds : nil
    }

    /// Adds a page, the oldest fading once `memory` are in.
    mutating func add(_ span: ReadingSpan, memory: Double) {
        if pages + 1 > memory {
            let keep = max(memory - 1, 0) / max(pages, 1)
            characters *= keep
            seconds *= keep
            pages *= keep
        }
        characters += Double(span.characters)
        seconds += span.seconds
        pages += 1
    }
}

/// Reading speed, overall and per book, kept on the device (#124,
/// `docs/notes/time-left.md`). Speeds are in characters, so they hold
/// folded, unfolded and at every text size.
public nonisolated struct ReadingPace: Codable, Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case counted
        /// Too quick to have been read.
        case leafing
        /// Too long to have been only reading.
        case pause
        /// Too little text to tell.
        case tooShort
    }

    public var overall = ReadingSpeed()
    /// By the book's storage key.
    public var books: [String: ReadingSpeed] = [:]

    public init() {}

    /// Whether there's a pace yet: until then, no time left is shown.
    public func hasPace(rules: ReadingPaceRules = .standard) -> Bool {
        overall.pages >= Double(rules.pagesForPace) && overall.perSecond != nil
    }

    /// The book's speed in characters a second: its own pages on top of a
    /// start at the overall speed. `nil` before there's a pace.
    public func speed(forBook book: String, rules: ReadingPaceRules = .standard) -> Double? {
        guard hasPace(rules: rules), overall.pages > 0 else { return nil }
        let prior = rules.bookPrior / overall.pages
        let own = books[book] ?? ReadingSpeed()
        let characters = overall.characters * prior + own.characters
        let seconds = overall.seconds * prior + own.seconds
        return seconds > 0 && characters > 0 ? characters / seconds : nil
    }

    /// Whether `span` was reading, judged by the book's speed (or the
    /// starting speed before there's one).
    public func judge(_ span: ReadingSpan, book: String, rules: ReadingPaceRules = .standard) -> Verdict {
        guard span.characters >= rules.minimumCharacters else { return .tooShort }
        let expected = Double(span.characters) / (speed(forBook: book, rules: rules) ?? rules.startingSpeed)
        if span.seconds < max(rules.leafingSeconds, expected * rules.leafingShare) { return .leafing }
        if span.seconds > max(rules.breakSeconds, expected * rules.breakShare) { return .pause }
        return .counted
    }

    /// Adds `span` to the book's speed and the overall one, if it counts.
    @discardableResult
    public mutating func record(_ span: ReadingSpan, book: String, rules: ReadingPaceRules = .standard) -> Verdict {
        let verdict = judge(span, book: book, rules: rules)
        guard verdict == .counted else { return verdict }
        overall.add(span, memory: rules.memory)
        books[book, default: ReadingSpeed()].add(span, memory: rules.memory)
        return verdict
    }

    /// Seconds to read `characters` of `book`, or `nil` before there's a pace.
    public func seconds(toRead characters: Double, book: String, rules: ReadingPaceRules = .standard) -> Double? {
        speed(forBook: book, rules: rules).map { max(characters, 0) / $0 }
    }

    /// Forgets the books whose keys `isRemoved` picks (a removed server's).
    public mutating func removeBooks(where isRemoved: (String) -> Bool) {
        books = books.filter { !isRemoved($0.key) }
    }
}

/// Time left as the footer rounds it: to the minute under an hour, to ten
/// minutes under ten hours, then to the hour.
public nonisolated enum ReadingTimeLeft: Equatable, Sendable {
    case underAMinute
    case minutes(Int)
    case hours(Int, minutes: Int)

    public init(seconds: Double) {
        let minutes = max(seconds, 0) / 60
        if minutes < 1 {
            self = .underAMinute
        } else if minutes.rounded() < 60 {
            self = .minutes(Int(minutes.rounded()))
        } else if minutes < 595 {
            let tens = Int((minutes / 10).rounded()) * 10
            self = .hours(tens / 60, minutes: tens % 60)
        } else {
            self = .hours(Int((minutes / 60).rounded()), minutes: 0)
        }
    }
}
