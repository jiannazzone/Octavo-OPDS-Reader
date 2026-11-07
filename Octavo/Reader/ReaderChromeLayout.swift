import Foundation

/// Who has the strip along the bottom of the page, and where what's in it
/// goes: the page's footer line, the way back after a jump (decision 33),
/// Search's step bar or BookOrbit's newer place in the footer's place, the
/// way back above the progress bar, and the line a note card or the tour's
/// card stops at. One place for the rules, so a new occupant changes them
/// here rather than adding an exception to each view
/// (`docs/notes/ui-audit.md`, item 18).
nonisolated struct ReaderChromeLayout: Equatable, Sendable {
    /// What's going on in the reader.
    nonisolated struct State: Equatable, Sendable {
        var isOpen = true
        /// A jump left a way back (`ReaderTrip`).
        var hasTrip = false
        var panelOpen = false
        var noteOpen = false
        var inTour = false
        /// Stepping through Search's matches.
        var searchStepping = false
        /// The server has a newer place to offer.
        var serverPlace: ReaderServerPlace?
        /// The progress bar and the column's buttons are up.
        var showsBar = false
        /// Two pages side by side.
        var twoPages = false
    }

    /// What takes the footer's place while no panel or progress bar is up.
    nonisolated enum FooterBar: Equatable, Sendable {
        case search
        case serverPlace(ReaderServerPlace)
    }

    var state: State

    /// The way back stays up with the controls hidden (decision 33). Not
    /// under a panel or a note, or on one page while Search's bar has the
    /// footer's place.
    var showsBackBar: Bool {
        guard state.hasTrip, !state.panelOpen, !state.noteOpen, !state.inTour, state.isOpen else { return false }
        return !(state.searchStepping && !state.twoPages)
    }

    var footerBar: FooterBar? {
        guard !state.panelOpen, !state.showsBar, !state.noteOpen, state.isOpen else { return nil }
        if state.searchStepping { return .search }
        return state.serverPlace.map(FooterBar.serverPlace)
    }

    /// On one page, BookOrbit's capsule stacks above the way back (decision
    /// 33). On two, they sit one under each page.
    var stacksOverBackBar: Bool {
        guard showsBackBar, !state.twoPages, case .serverPlace = footerBar else { return false }
        return true
    }

    /// The bars take the footer's place, except that on one page the way back
    /// keeps the numbers beside it, with BookOrbit's capsule above.
    var showsFooter: Bool {
        !state.showsBar && (footerBar == nil || stacksOverBackBar)
    }

    /// The way back sits in the chapter's place (decision 33).
    var hidesFooterChapter: Bool { showsBackBar }

    // MARK: Where things go

    /// The footer line's height (`ReaderFooterLines`).
    static let footerLineHeight = 20.0
    /// Between the bars in the strip, and above the home indicator's edge.
    static let barGap = 4.0
    /// Between the way back and what's under it.
    static let backBarGap = 6.0
    /// Between the way back and the progress bar under it.
    static let aboveBarGap = 8.0

    /// The middle of the page's footer line: the middle of foliate's bottom
    /// margin.
    static func footerLineCentre(in geometry: ReaderGeometry, layout: ReaderLayout) -> Double {
        Double(geometry.size.height) - layout.bottomInset - ReaderLayout.verticalMargin / 2
    }

    /// The top of the footer line, which a note card stops above.
    static func footerLineTop(in geometry: ReaderGeometry, layout: ReaderLayout) -> Double {
        footerLineCentre(in: geometry, layout: layout) - footerLineHeight / 2
    }

    /// The way back's top: in the footer line's place, or just above the
    /// progress bar while it's up (`barHeight`, as it measured itself).
    func backBarTop(in geometry: ReaderGeometry, layout: ReaderLayout, barHeight: Double) -> Double {
        if state.showsBar {
            return ReaderLayout.barBottom(in: geometry) - barHeight - Self.aboveBarGap - ReaderBackBar.height
        }
        return Self.footerLineCentre(in: geometry, layout: layout) - ReaderBackBar.height / 2
    }

    /// Where the footer bar runs: under the page, or under the right page of
    /// a spread, as nothing spans the hinge (decision 9).
    static func footerBarSpan(in geometry: ReaderGeometry, layout: ReaderLayout) -> (left: Double, width: Double) {
        let right = Double(geometry.size.width) - geometry.safeArea.right
        let left = layout.columns == 2 ? (layout.fold?.upperBound ?? geometry.safeArea.left) : geometry.safeArea.left
        return (left, max(0, right - left))
    }

    /// How far the footer bar's bottom is from the window's: on the home
    /// indicator's edge, and above the way back when it stacks over it.
    func footerBarBottomInset(in geometry: ReaderGeometry) -> Double {
        let edge = Double(geometry.size.height) - ReaderLayout.barBottom(in: geometry) + Self.barGap
        return edge + (stacksOverBackBar ? ReaderBackBar.height + Self.backBarGap : 0)
    }

    /// The tour's card's bottom: above an open panel's sheet along one page,
    /// or clear of where the progress bar comes up (`barClearance`, which the
    /// card scales with the text).
    static func tourCardBottom(in geometry: ReaderGeometry, sheetHeight: Double?, barClearance: Double) -> Double {
        if let sheetHeight {
            return ReaderLayout.barBottom(in: geometry) - sheetHeight - aboveBarGap
        }
        return ReaderLayout.barBottom(in: geometry) - barClearance
    }
}
