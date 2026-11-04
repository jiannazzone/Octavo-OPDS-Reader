import Foundation

/// Where the reader is, in words: the chapter, the page numbers and the
/// percentage shown in each page's footer and on the progress bar
/// (decision 7).
///
/// Page numbers are foliate's locations: the book cut into pieces of 1,500
/// characters, the same on every device and in every layout (so they don't
/// move when the phone folds), though a turn doesn't always change the
/// number. A fixed-layout book's are its own pages.
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

/// What the progress bar's right-hand piece shows in book mode, under the
/// right page (Adam, 2026-11-03). One readout at a time: time left in the
/// chapter joins once Octavo measures reading speed, and choosing which
/// shows is for later (`docs/UI-IDEAS.md`).
nonisolated enum ReaderBarReadout: Sendable {
    /// Pages left in the chapter, over a line through it.
    case chapter
    /// The book's page numbers and percentage.
    case pages

    static let standard = ReaderBarReadout.chapter
}

/// How far through its chapter a place is. The chapter is the contents
/// entry the place falls in (the one the bar names) and runs to the next
/// entry; pages are the footer's.
nonisolated struct ReaderChapterProgress: Equatable, Sendable {
    /// Pages after the ones on screen, before the next entry starts.
    var pagesLeft: Int
    /// 0...1 through the chapter, counting the pages on screen as read.
    var fraction: Double

    /// `nil` before the first entry, or without locations.
    init?(place: ReaderPlace, toc: [ReaderMessage.TOCEntry]) {
        let starts = toc.compactMap(\.fraction)
        guard let last = place.last, let total = place.total,
              let start = starts.filter({ $0 <= place.fraction + 1e-9 }).max()
        else { return nil }
        let end = starts.filter { $0 > start + 1e-9 }.min()
        let page = { (fraction: Double) in ReaderPlace(fraction: fraction, toc: [], total: total).first ?? 1 }
        let firstPage = page(start)
        let nextFirstPage = end.map(page) ?? total + 1
        pagesLeft = max(0, nextFirstPage - 1 - last)
        fraction = min(max(Double(last - firstPage + 1) / Double(max(1, nextFirstPage - firstPage)), 0), 1)
    }

    /// "6 pages left in this chapter".
    var text: String {
        switch pagesLeft {
        case 0: String(localized: "Last page of this chapter", comment: "Progress bar, book mode: the chapter ends on this spread")
        case 1: String(localized: "1 page left in this chapter", comment: "Progress bar, book mode: pages after this spread in its chapter")
        default: String(localized: "\(pagesLeft) pages left in this chapter", comment: "Progress bar, book mode: pages after this spread in its chapter")
        }
    }
}

/// What the controls show (decision 7, approved 2026-11-01): the column's
/// buttons, and the progress bar over the page.
///
/// - The column's "…" button shows both (Adam, 2026-11-02, every posture);
///   the next tap anywhere on the page hides them.
/// - With "Always show controls" the buttons stay up, the "…" after them
///   bringing up the bar. The buttons sit in the column, so they never
///   cover text; the bar does, so it never stays.
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

    /// The column's "…" button.
    mutating func show() {
        showsButtons = true
        showsBar = true
    }

    /// VoiceOver's Show/Hide Controls.
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

    private var barBeforePanel = false

    /// A panel opening (#18): the buttons stay, the panel growing out of
    /// its own (Adam, 2026-11-02); the bar goes, as it would run under the
    /// panel.
    mutating func panelOpened() {
        barBeforePanel = showsBar
        showsButtons = true
        showsBar = false
    }

    /// The panel's own button closing it: the controls as they were.
    mutating func panelClosed() {
        showsBar = barBeforePanel
    }
}
