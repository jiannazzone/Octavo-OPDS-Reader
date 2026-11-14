import Foundation
import Observation
import OctavoKit

/// Reading speed on this iPhone, overall and per book (#124,
/// `docs/notes/time-left.md`), in one small file. Never synced.
@Observable
final class ReadingPaceStore {
    static let shared = ReadingPaceStore()

    private(set) var pace: ReadingPace
    @ObservationIgnored let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "ReadingPace.json", directoryHint: .notDirectory)) {
        self.fileURL = fileURL
        pace = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(ReadingPace.self, from: $0) } ?? ReadingPace()
    }

    /// Adds `span` if it was reading, and saves.
    @discardableResult
    func record(_ span: ReadingSpan, book: String) -> ReadingPace.Verdict {
        var pace = pace
        let verdict = pace.record(span, book: book)
        if verdict == .counted {
            self.pace = pace
            save()
        }
        return verdict
    }

    /// Forgets `library`'s books (Remove server).
    func removeAll(of library: LibrarySourceID) {
        let prefix = StoredBookKeys.prefix(of: library)
        pace.removeBooks { $0.hasPrefix(prefix) }
        save()
    }

    /// Gives `library`'s books to `other` (`RemovedServer`), keeping any
    /// `other` already has.
    func moveAll(of library: LibrarySourceID, to other: LibrarySourceID) {
        let from = StoredBookKeys.prefix(of: library), to = StoredBookKeys.prefix(of: other)
        var pace = pace
        for (key, speed) in pace.books where key.hasPrefix(from) {
            let moved = to + key.dropFirst(from.count)
            if pace.books[moved] == nil { pace.books[moved] = speed }
        }
        pace.removeBooks { $0.hasPrefix(from) }
        self.pace = pace
        save()
    }

    /// Starts again from nothing (tests and the debug switches).
    func reset() {
        pace = ReadingPace()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(pace).write(to: fileURL, options: .atomic)
    }
}

/// Times the page on screen. A turn forward by a page hands back the page
/// left, for `ReadingPace` to judge; anything else (a jump, a fold, going
/// back, opening, leaving the app) starts the clock again.
nonisolated struct ReaderPaceClock: Equatable, Sendable {
    private var since: Date?
    private var characters: Int?
    private var fraction = 0.0

    /// The page at `fraction` with `characters` came on screen at `date`.
    /// `turnedForward`: a page turn on from the last page, which then
    /// counts as read.
    mutating func arrived(fraction: Double, characters: Int?, turnedForward: Bool, at date: Date) -> ReadingSpan? {
        defer {
            since = date
            self.characters = characters
            self.fraction = fraction
        }
        guard turnedForward, fraction > self.fraction, let since, let read = self.characters, date > since else { return nil }
        return ReadingSpan(start: since, end: date, characters: read)
    }

    /// Nothing on screen is being timed (the app left, or the book closed).
    mutating func stop() {
        since = nil
    }

    /// Times the page on screen again from `date` (the app came back).
    mutating func restart(at date: Date) {
        if characters != nil { since = date }
    }
}

/// Time left to read, from the book's characters and its speed.
nonisolated struct ReaderTimeLeft: Equatable, Sendable {
    let map: BookTextMap
    let toc: [ReaderMessage.TOCEntry]
    /// Characters a second.
    let speed: Double

    /// Seconds from the page at `fraction` to the next contents entry (the
    /// book's end after the last).
    func chapter(from fraction: Double) -> Double? {
        let end = toc.compactMap(\.fraction).filter { $0 > fraction + 1e-9 }.min() ?? 1
        return map.characters(from: fraction, to: end).map { $0 / speed }
    }

    /// Seconds from the page at `fraction` to the book's end.
    func book(from fraction: Double) -> Double? {
        map.characters(from: fraction, to: 1).map { $0 / speed }
    }
}

/// What the footer's numbers show (#124): a tap goes to the next, the
/// choice is for every book. Time left joins once there's a pace.
nonisolated enum ReaderFooterReadout: String, CaseIterable, Sendable {
    case chapterTime
    case bookTime
    case page
    case percent

    static let key = "reader.footerReadout"
    static let standard = ReaderFooterReadout.chapterTime

    var isTime: Bool { self == .chapterTime || self == .bookTime }

    /// The readout to show for this choice: a time one waits for a pace on
    /// page, and page without locations on percent.
    func shown(hasTime: Bool, hasPages: Bool) -> ReaderFooterReadout {
        if isTime, !hasTime { return hasPages ? .page : .percent }
        if self == .page, !hasPages { return .percent }
        return self
    }

    /// The one after `self` that can show.
    func next(hasTime: Bool, hasPages: Bool) -> ReaderFooterReadout {
        let all = Self.allCases
        var index = all.firstIndex(of: self)!
        for _ in all {
            index = (index + 1) % all.count
            let candidate = all[index]
            if candidate.shown(hasTime: hasTime, hasPages: hasPages) == candidate { return candidate }
        }
        return self
    }
}

/// The footer's time left in words.
nonisolated enum ReaderTimeLeftText {
    enum Scope { case chapter, book }

    /// "12 min left in chapter", "3 h 40 min left in book".
    static func short(_ time: ReadingTimeLeft, _ scope: Scope) -> String {
        switch (time, scope) {
        case (.underAMinute, .chapter):
            String(localized: "Under 1 min left in chapter", comment: "Reader footer: reading time left in the chapter")
        case (.underAMinute, .book):
            String(localized: "Under 1 min left in book", comment: "Reader footer: reading time left in the book")
        case (.minutes(let minutes), .chapter):
            String(localized: "\(minutes) min left in chapter", comment: "Reader footer: reading time left in the chapter, e.g. 12 min")
        case (.minutes(let minutes), .book):
            String(localized: "\(minutes) min left in book", comment: "Reader footer: reading time left in the book, e.g. 12 min")
        case (.hours(let hours, 0), .chapter):
            String(localized: "\(hours) h left in chapter", comment: "Reader footer: reading time left in the chapter, e.g. 12 h")
        case (.hours(let hours, 0), .book):
            String(localized: "\(hours) h left in book", comment: "Reader footer: reading time left in the book, e.g. 12 h")
        case (.hours(let hours, let minutes), .chapter):
            String(localized: "\(hours) h \(minutes) min left in chapter", comment: "Reader footer: reading time left in the chapter, e.g. 3 h 40 min")
        case (.hours(let hours, let minutes), .book):
            String(localized: "\(hours) h \(minutes) min left in book", comment: "Reader footer: reading time left in the book, e.g. 3 h 40 min")
        }
    }

    /// For VoiceOver, in whole words: "3 hours, 40 minutes left in book".
    static func spoken(_ time: ReadingTimeLeft, _ scope: Scope) -> String {
        let duration: Duration
        switch time {
        case .underAMinute:
            return scope == .chapter
                ? String(localized: "Less than a minute left in chapter", comment: "VoiceOver: reading time left in the chapter")
                : String(localized: "Less than a minute left in book", comment: "VoiceOver: reading time left in the book")
        case .minutes(let minutes): duration = .seconds(minutes * 60)
        case .hours(let hours, let minutes): duration = .seconds((hours * 60 + minutes) * 60)
        }
        let words = duration.formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return scope == .chapter
            ? String(localized: "\(words) left in chapter", comment: "VoiceOver: reading time left in the chapter, e.g. 3 hours, 40 minutes")
            : String(localized: "\(words) left in book", comment: "VoiceOver: reading time left in the book, e.g. 3 hours, 40 minutes")
    }
}
