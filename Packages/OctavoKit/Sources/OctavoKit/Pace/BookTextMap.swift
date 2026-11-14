import Foundation

/// How many characters of text each section of a book holds, for turning a
/// place in the book (foliate's fraction, 0...1) into characters before it
/// (#124, `docs/notes/time-left.md`).
///
/// foliate's fractions count each section's bytes, markup and all, so a
/// section's share of the book isn't its share of the words. Within a
/// section a place is placed by characters or by page, close enough to
/// characters to go straight across.
public nonisolated struct BookTextMap: Codable, Equatable, Sendable {
    /// Each section's characters, in reading order; `nil` for one that
    /// couldn't be read.
    public var sections: [Int?]
    /// Where each section starts in the book, and the book's end:
    /// `sections.count + 1` of them.
    public var starts: [Double]

    /// `nil` unless there's a start for each section and the end.
    public init?(sections: [Int?], starts: [Double]) {
        guard !sections.isEmpty, starts.count == sections.count + 1 else { return nil }
        self.sections = sections
        self.starts = starts
    }

    /// Every character in the book, or `nil` if a section couldn't be read.
    public var total: Int? {
        sections.reduce(0 as Int?) { sum, count in sum.flatMap { sum in count.map { sum + max($0, 0) } } }
    }

    /// The characters before `fraction`. `nil` if a section up to it
    /// couldn't be read.
    public func characters(before fraction: Double) -> Double? {
        let fraction = min(max(fraction, 0), 1)
        var before = 0.0
        for (index, count) in sections.enumerated() {
            let start = starts[index], end = starts[index + 1]
            if fraction <= start { return before }
            guard let count else { return nil }
            if fraction < end, end > start {
                return before + Double(max(count, 0)) * (fraction - start) / (end - start)
            }
            before += Double(max(count, 0))
        }
        return before
    }

    /// The characters from `start` to `end` (0 if `end` comes first).
    public func characters(from start: Double, to end: Double) -> Double? {
        guard let first = characters(before: start), let last = characters(before: end) else { return nil }
        return max(0, last - first)
    }
}
