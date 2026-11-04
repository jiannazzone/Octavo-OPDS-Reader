import Foundation

/// What the scrubber's line shows and how it zooms (decision 35): dots at
/// chapters and a free knob across the whole book; hold still and it zooms in
/// around the finger, each dot a page, with bars at chapter starts that catch
/// the knob. Positions are fractions of the book; `travel` is how far the
/// knob's centre moves from one end of the line to the other.
nonisolated struct ReaderScrubberLine: Equatable, Sendable {
    /// Zoomed in, the points of line per page.
    static let pointsPerPage = 8.0
    /// Zoomed in, how far either side of a chapter's start the knob catches.
    static let catchPoints = 3.0
    /// Across the whole book, the least room between two chapters' dots.
    static let minimumDotGap = 6.0
    /// How much of its own length a zoomed line slides each second, at its
    /// ends.
    static let slideRate = 0.5
    /// How near the ends of a zoomed line it starts to slide, as a share of it.
    static let slideEdge = 0.07

    static let wholeBook = 0.0...1.0

    /// In reading order, each once.
    let chapters: [Double]
    let total: Int?
    let travel: Double

    init(chapters: [Double], total: Int?, travel: Double) {
        self.chapters = Array(Set(chapters)).sorted()
        self.total = total
        self.travel = travel
    }

    /// The zoomed line around `value`, with the knob staying where it is on
    /// the line (`nil` when the whole book already gives a page that much
    /// room). Near the book's ends it stops at them, so the knob moves a
    /// little.
    func zoomed(around value: Double, in window: ClosedRange<Double>) -> ClosedRange<Double>? {
        guard let total, total > 0, travel > 0 else { return nil }
        let width = travel / Self.pointsPerPage / Double(total)
        guard width < 1 else { return nil }
        let ratio = (value - window.lowerBound) / Self.length(of: window)
        let low = min(max(value - ratio * width, 0), 1 - width)
        return low...(low + width)
    }

    /// The chapters' dots across the whole book, none closer than
    /// `minimumDotGap` to the one before.
    var chapterDots: [Double] {
        guard travel > 0 else { return [] }
        var kept: [Double] = []
        for chapter in chapters where (kept.last.map { (chapter - $0) * travel >= Self.minimumDotGap } ?? true) {
            kept.append(chapter)
        }
        return kept
    }

    /// Zoomed in: a dot for each page in `window`.
    func pageDots(in window: ClosedRange<Double>) -> [Double] {
        guard let total, total > 0 else { return [] }
        let first = Int((window.lowerBound * Double(total)).rounded(.up))
        let last = Int((window.upperBound * Double(total)).rounded(.down))
        guard first <= last else { return [] }
        return (first...last).map { Double($0) / Double(total) }
    }

    /// Zoomed in: the chapters that start in `window`.
    func chapterBars(in window: ClosedRange<Double>) -> [Double] {
        chapters.filter(window.contains)
    }

    /// Zoomed in: the chapter whose start holds a knob at `value`.
    func caughtChapter(near value: Double, in window: ClosedRange<Double>) -> Double? {
        let perPoint = Self.length(of: window) / travel
        return chapterBars(in: window)
            .min { abs($0 - value) < abs($1 - value) }
            .flatMap { abs($0 - value) < Self.catchPoints * perPoint ? $0 : nil }
    }

    /// Which chapter `value` falls in, for the tick as the knob passes one.
    func chapterIndex(at value: Double) -> Int? {
        chapters.lastIndex { $0 <= value }
    }

    /// The window `elapsed` seconds on, with the knob at `ratio` along it: at
    /// the ends of a zoomed line it slides on through the book. `nil` when it
    /// stays put.
    static func slid(_ window: ClosedRange<Double>, knobAt ratio: Double, elapsed: Double) -> ClosedRange<Double>? {
        guard ratio < slideEdge || ratio > 1 - slideEdge else { return nil }
        let width = length(of: window)
        let shift = width * slideRate * elapsed * (ratio < 0.5 ? -1 : 1)
        let low = min(max(window.lowerBound + shift, 0), 1 - width)
        guard low != window.lowerBound else { return nil }
        return low...(low + width)
    }

    /// Never zero, for dividing by.
    static func length(of window: ClosedRange<Double>) -> Double {
        max(window.upperBound - window.lowerBound, .leastNonzeroMagnitude)
    }
}

/// Whether the finger is moving quickly: a quick move zooms back out. Read
/// over the last moments, as touches can arrive together, and a pause before
/// a move shouldn't count against it.
nonisolated struct ReaderScrubberSpeed: Equatable, Sendable {
    /// Points a second.
    static let quick = 500.0
    static let span = 0.12
    static let leastTime = 0.03
    static let leastDistance = 12.0

    private struct Sample: Equatable {
        var time: Double
        var points: Double
    }

    private var samples: [Sample] = []

    /// The finger at `points` along the line, at `time` in seconds.
    mutating func moved(to points: Double, at time: Double) -> Bool {
        samples.append(Sample(time: time, points: points))
        samples.removeAll { time - $0.time > Self.span }
        guard let first = samples.first, time - first.time >= Self.leastTime else { return false }
        let distance = abs(points - first.points)
        return distance >= Self.leastDistance && distance / (time - first.time) > Self.quick
    }

    mutating func reset() {
        samples = []
    }
}
