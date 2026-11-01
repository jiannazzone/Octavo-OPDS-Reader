import Foundation

/// Where the reader is, in words: the chapter, the page numbers and the
/// percentage shown in each page's footer and on the progress bar
/// (decision 7).
///
/// Page numbers are foliate's locations: the book cut into pieces of 1,500
/// characters, the same on every device and in every layout (so they don't
/// move when the phone folds), though a turn doesn't always change the
/// number.
nonisolated struct ReaderPlace: Equatable, Sendable {
    var chapter: String?
    /// The first location shown, from 1.
    var first: Int?
    /// The last location shown (a spread can show two).
    var last: Int?
    var total: Int?
    var fraction: Double

    init(chapter: String?, location: ReaderMessage.Relocation.Location?, fraction: Double) {
        self.chapter = chapter
        self.fraction = min(max(fraction, 0), 1)
        if let current = location?.current, let total = location?.total, total > 0 {
            let first = min(current + 1, total)
            self.first = first
            self.last = min(max(first, (location?.next ?? current) + 1), total)
            self.total = total
        }
    }

    /// A point of the progress bar: the chapter there and the location it
    /// falls in.
    init(fraction: Double, toc: [ReaderMessage.TOCEntry], total: Int?) {
        let fraction = min(max(fraction, 0), 1)
        let location = total.map { total in
            ReaderMessage.Relocation.Location(current: min(Int(fraction * Double(total)), max(total - 1, 0)), total: total)
        }
        self.init(chapter: Self.chapterName(at: fraction, in: toc), location: location, fraction: fraction)
    }

    /// The last contents entry starting at or before `fraction`.
    static func chapterName(at fraction: Double, in toc: [ReaderMessage.TOCEntry]) -> String? {
        toc.last { ($0.fraction ?? .infinity) <= fraction + 1e-9 }?.label
    }

    /// "30%". Rounded down, so 100% means the end.
    var percent: String {
        fraction.formatted(.percent.precision(.fractionLength(0)).rounded(rule: .down))
    }

    /// "291 of 974", or "291–292 of 974" when `spread` shows two locations.
    func pages(spread: Bool) -> String? {
        guard let first, let last, let total else { return nil }
        if spread, last > first {
            return String(localized: "\(first)–\(last) of \(total)", comment: "Locations shown on a spread, out of the book's total")
        }
        return String(localized: "\(first) of \(total)", comment: "The page's location, out of the book's total")
    }

    /// The footer's numbers: "291 of 974 · 30%".
    func footer(spread: Bool) -> String {
        pages(spread: spread).map { "\($0) · \(percent)" } ?? percent
    }

    /// The progress bar's numbers: "Page 291 of 974 · 30%".
    func barLine(spread: Bool) -> String {
        guard let pages = pages(spread: spread), let first, let last else { return percent }
        let line = spread && last > first
            ? String(localized: "Pages \(pages)", comment: "Progress bar: the spread's locations, e.g. Pages 291–292 of 974")
            : String(localized: "Page \(pages)", comment: "Progress bar: the page's location, e.g. Page 291 of 974")
        return "\(line) · \(percent)"
    }
}

/// What the controls show (decision 7, approved 2026-11-01): the column's
/// buttons, and the progress bar over the page.
///
/// - A tap in the middle (flat) or in the side column (book mode) shows both;
///   the next tap anywhere on the page hides them.
/// - With "Always show controls" the buttons stay up and the tap shows and
///   hides only the bar. The buttons sit in the column, so they never cover
///   text; the bar does, so it never stays.
/// - Book mode starting hides them (decision 9).
nonisolated struct ReaderControls: Equatable, Sendable {
    var alwaysShowsButtons = false
    private(set) var showsButtons = false
    private(set) var showsBar = false

    init(alwaysShowsButtons: Bool = false) {
        self.alwaysShowsButtons = alwaysShowsButtons
    }

    var buttonsVisible: Bool { alwaysShowsButtons || showsButtons }
    /// The bar lies over the page, so a tap should hide it, not turn.
    var coversPage: Bool { showsBar }

    /// A tap in the middle of the page, or in the side column in book mode.
    mutating func toggle() {
        if alwaysShowsButtons {
            showsBar.toggle()
        } else {
            let show = !(showsButtons || showsBar)
            showsButtons = show
            showsBar = show
        }
    }

    mutating func hide() {
        showsButtons = false
        showsBar = false
    }
}
