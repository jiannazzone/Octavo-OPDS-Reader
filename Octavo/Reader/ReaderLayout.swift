import CoreGraphics
import Foundation

/// The device's fold, as far as the reader cares. Mapped from SwiftUI's
/// `DeviceHingeContext` in `ReaderWebView`.
nonisolated enum ReaderPosture: String, Equatable, Sendable, Codable {
    /// No hinge reported: a device without one, or not known yet.
    case noHinge
    case closed
    case halfOpen
    case open
}

/// Distances in points from the page's edges, in physical directions (left
/// and right, not leading and trailing): the page lays out in physical
/// coordinates.
nonisolated struct ReaderInsets: Equatable, Sendable, Codable {
    var top = 0.0
    var left = 0.0
    var bottom = 0.0
    var right = 0.0

    static let zero = ReaderInsets()
}

/// Where the reader sits relative to the fold and the system's areas: its
/// size, the hinge's `division` reserved regions in its own coordinates (not
/// mirrored for right-to-left, because the web page lays out in physical
/// coordinates), and the safe area.
///
/// On iPhone Duo (iOS 27.1 simulator) the division region is the hinge line
/// plus 20pt margins each side, the full height of the screen. It's reported
/// only on the inner display, inactive when flat and active when half open.
/// The safe area is the side column (84 pt on the trailing edge, held
/// upright), or a band along the top when the open phone is turned sideways.
nonisolated struct ReaderGeometry: Equatable, Sendable, Codable {
    nonisolated struct Region: Equatable, Sendable, Codable {
        /// Includes the margins the system asks interactive content to keep.
        var frame: CGRect
        var isActive: Bool
    }

    var size: CGSize
    var divisions: [Region] = []
    /// The page runs edge to edge (decision 8); text stays inside this.
    var safeArea = ReaderInsets.zero
}

/// The margins setting (decision 8), a slider's five steps from narrow to
/// wide: foliate ties the outer margins and the gutter between two pages
/// together as its `gap`, a share of the page area's width. Narrow, Medium
/// and Wide approved 2026-11-01; the steps between them 2026-11-07, each
/// halfway between its neighbours on the page. The Customize panel (#18)
/// binds to `key`; the raw values are what's saved.
nonisolated enum ReaderMargins: String, CaseIterable, Sendable, Codable {
    /// Text reaches the side column's edge: the margin itself lies under
    /// the column. Unfolded, the gutter is a point wider than the hinge's
    /// 40 pt.
    case narrow
    /// Two fifths of the margin under the column: 23 pt folded, ending
    /// 14 pt short of the column; unfolded a 48 pt gutter and 29 pt from
    /// the column.
    case mediumNarrow
    /// The frames (07–09): foliate's own 7%, 27 pt folded and 55 pt
    /// unfolded (to the whole point).
    case medium
    /// 32 pt folded, 67 pt unfolded.
    case mediumWide
    case wide

    static let key = "reader.margins"
    static let standard = ReaderMargins.medium

    /// foliate's `gap`, in percent of the page area's width.
    var gapPercent: Double {
        switch self {
        case .narrow: 4.6
        case .mediumNarrow: 5.8
        case .medium: 7
        case .mediumWide: 8.5
        case .wide: 10
        }
    }

    /// How much of the margin lies under the side column (and, unfolded,
    /// the strip that mirrors it), so the text reaches towards it. Narrow
    /// all of it; the step after it enough to sit halfway to Medium, which
    /// reaches none.
    var underColumn: Double {
        switch self {
        case .narrow: 1
        case .mediumNarrow: 0.4
        case .medium, .mediumWide, .wide: 0
        }
    }

    /// What VoiceOver reads for the step; only Narrow and Wide show, at the
    /// slider's ends.
    var name: String {
        switch self {
        case .narrow: "Narrow"
        case .mediumNarrow: "Fairly Narrow"
        case .medium: "Medium"
        case .mediumWide: "Fairly Wide"
        case .wide: "Wide"
        }
    }

    /// The slider's step, 0 for Narrow to 4 for Wide.
    var step: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    init(step: Int) {
        self = Self.allCases[min(max(step, 0), Self.allCases.count - 1)]
    }
}

/// How foliate-js lays out pages, decided from the posture, where the fold
/// runs through the reader, the safe area and the margins setting. Applied
/// by `bridge.js` `setLayout`.
///
/// foliate centres its column gap in the middle of the `foliate-view`, and
/// with equal spacing the gap is `gap`% of the view's width (the outer margins
/// match it). So a spread whose gap sits over the fold needs the view centred
/// on the fold (`leftInset`/`rightInset`) and a gap at least as wide as the
/// fold's region.
///
/// The page itself runs edge to edge; the insets keep the `foliate-view`, and
/// so the text, out of the side column (decision 8).
nonisolated struct ReaderLayout: Equatable, Sendable, Codable {
    /// Pages side by side. `nil` leaves it to foliate (two when the reader
    /// area is landscape and wide enough, else one).
    var columns: Int?
    /// foliate's `gap`, in percent of the view's width. `nil` = foliate's 7%.
    var gapPercent: Double?
    /// foliate's `max-inline-size` in CSS px. `nil` = foliate's 720px.
    var maxInlineSize: Double?
    /// CSS px trimmed off the `foliate-view`'s edges.
    var leftInset: Double = 0
    var rightInset: Double = 0
    var topInset: Double = 0
    var bottomInset: Double = 0
    /// The fold's horizontal extent in the reader, when the gap is meant to
    /// cover it. Used only for checking where text lands.
    var fold: ClosedRange<Double>?

    /// foliate-js's default `gap`.
    static let defaultGapPercent = 7.0
    /// foliate-js's default `max-inline-size`, in CSS px.
    static let defaultMaxInlineSize = 720.0
    /// foliate's top and bottom margin (`--_margin`), where the footer sits.
    static let verticalMargin = 48.0
    /// A page narrower than this either side of the fold isn't worth a spread.
    static let minimumPageWidth = 200.0

    /// Whatever foliate does on its own.
    static let automatic = ReaderLayout()
    /// One page, foliate's spacing.
    static let single = ReaderLayout(columns: 1)

    init(columns: Int? = nil, gapPercent: Double? = nil, maxInlineSize: Double? = nil,
         leftInset: Double = 0, rightInset: Double = 0, topInset: Double = 0, bottomInset: Double = 0,
         fold: ClosedRange<Double>? = nil) {
        self.columns = columns
        self.gapPercent = gapPercent
        self.maxInlineSize = maxInlineSize
        self.leftInset = leftInset
        self.rightInset = rightInset
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.fold = fold
    }

    /// - Closed: one page.
    /// - Open or half open with a fold running top to bottom: two pages, the
    ///   gap over the fold. The region counts even when inactive (flat): the
    ///   crease is still there.
    /// - Open with the fold running across (device turned): one page, straight
    ///   across the fold (decision 12).
    /// - Open without any region reported: two pages around the middle if
    ///   the reader is landscape, else one. (During an unfold the hinge
    ///   reports open a moment before the reader takes the inner display's
    ///   size.)
    /// - No hinge reported: a spread if a fold runs top to bottom, active or
    ///   not, otherwise foliate decides the columns. The region alone is
    ///   enough on the Duo's inner display, so a hinge report that comes
    ///   late (or, after a cold launch, not at all until the hinge moves; seen
    ///   once in #4) never puts text on the fold.
    ///
    /// `buttonsOnTop`: the clock and the buttons are in a band along the top
    /// (`ReaderSettings.buttonsOnTopKey`), which foliate's top margin overlaps.
    init(posture: ReaderPosture, geometry: ReaderGeometry?, margins: ReaderMargins = .standard, buttonsOnTop: Bool = false) {
        let geometry = geometry ?? ReaderGeometry(size: .zero)
        let width = Double(geometry.size.width)
        let size = geometry.size
        let single = Self.single(in: geometry, margins: margins)
        switch posture {
        case .closed:
            self = single
        case .open, .halfOpen:
            if let spine = Self.spine(in: geometry, includeInactive: true) {
                self = .spread(in: geometry, fold: spine, margins: margins)
            } else if !geometry.divisions.isEmpty || size.width <= size.height
                        || width < 2 * Self.minimumPageWidth {
                self = single
            } else {
                self = .spread(in: geometry, fold: nil, margins: margins)
            }
        case .noHinge:
            if let spine = Self.spine(in: geometry, includeInactive: true) {
                self = .spread(in: geometry, fold: spine, margins: margins)
            } else {
                self = single
                columns = nil
            }
        }
        if buttonsOnTop {
            topInset = max(0, topInset - Self.topBarOverlap)
        }
    }

    /// How far foliate's 48 pt top margin reaches into the band of buttons
    /// along the top. The band is 82 pt and its buttons end near 72 pt, so
    /// the first line starts about 16 pt below them (#136,
    /// `docs/notes/edge-margin.md`), not 60.
    static let topBarOverlap = 46.0

    /// A division region that runs top to bottom through the reader with room
    /// for a page on each side. Active regions first.
    static func spine(in geometry: ReaderGeometry, includeInactive: Bool) -> CGRect? {
        let size = geometry.size
        return geometry.divisions
            .filter { includeInactive || $0.isActive }
            .sorted { $0.isActive && !$1.isActive }
            .map(\.frame)
            .first { frame in
                frame.height > frame.width
                    && frame.minY <= size.height * 0.25
                    && frame.maxY >= size.height * 0.75
                    && Double(frame.midX) - Double(frame.width) / 2 >= minimumPageWidth
                    && Double(size.width - frame.midX) - Double(frame.width) / 2 >= minimumPageWidth
            }
    }

    /// One page across the safe area's width. The view reaches under each
    /// side's inset by the share of its margin the setting puts there
    /// (`underColumn`): with Narrow, all of it, so the text meets the
    /// inset's edge.
    ///
    /// The view and the margin are whole points (`wholePageGap`).
    static func single(in geometry: ReaderGeometry, margins: ReaderMargins) -> ReaderLayout {
        let safe = geometry.safeArea
        let width = Double(geometry.size.width)
        let content = max(0, width - safe.left - safe.right)
        let share = margins.gapPercent / 100
        let reachLeft = safe.left > 0 ? margins.underColumn : 0
        let reachRight = safe.right > 0 ? margins.underColumn : 0
        let sides = reachLeft + reachRight
        let margin = (share * content / (1 - sides * share)).rounded()
        let view = (content + sides * margin).rounded(.down)
        // Rounding the view down takes the fraction off the left, so the text
        // still ends where the setting puts it against the right-hand inset.
        let right = max(0, Self.snapped(safe.right - reachRight * margin))
        let left = max(0, width - right - view)
        return ReaderLayout(
            columns: 1, gapPercent: Self.gapPercent(margin, of: view, else: margins.gapPercent),
            leftInset: left, rightInset: right, topInset: safe.top, bottomInset: safe.bottom
        )
    }

    /// Two pages with foliate's view centred on `fold` (or on the middle of
    /// the safe area) and a gap a point wider than the fold, so the text
    /// stays half a point clear of it each side. The view is as wide as the
    /// shorter side allows, so the margins match on both sides (unfolded,
    /// the left edge gives up what the side column takes on the right).
    /// The view reaches under both edges by the share of the margin the
    /// setting puts there (`underColumn`): with Narrow, all of it.
    ///
    /// The view and the gap are whole points (`wholePageGap`).
    static func spread(in geometry: ReaderGeometry, fold: CGRect?, margins: ReaderMargins) -> ReaderLayout {
        let safe = geometry.safeArea
        let width = Double(geometry.size.width)
        let contentLeft = safe.left
        let contentRight = width - safe.right
        let mid = fold.map { Double($0.midX) } ?? (contentLeft + contentRight) / 2
        let half = max(0, min(mid - contentLeft, contentRight - mid))
        let foldWidth = Double(fold?.width ?? 0)
        let reach = margins.underColumn
        let share = margins.gapPercent / 100
        // The setting's gap, `share` of the view, which includes the part of
        // the gap reaching under each edge.
        let setting = share * 2 * half / (1 - 2 * reach * share)
        let gap = max(setting.rounded(), foldWidth > 0 ? (foldWidth + 1).rounded(.up) : 0)
        let view = (2 * half + 2 * reach * gap).rounded(.down)
        let left = Self.snapped(mid - view / 2)
        return ReaderLayout(
            columns: 2,
            gapPercent: Self.gapPercent(gap, of: view, else: margins.gapPercent),
            // At half the view, foliate fits exactly two columns and never caps
            // the text width, which would move the gap off-centre.
            maxInlineSize: (view / 2).rounded(.up),
            leftInset: max(0, left),
            rightInset: max(0, width - (left + view)),
            topInset: safe.top,
            bottomInset: safe.bottom,
            fold: fold.map { Double($0.minX)...Double($0.maxX) }
        )
    }

    /// foliate turns a page by scrolling `page × page width`, and WebKit
    /// keeps a scroll offset in whole points. A page width with a fraction
    /// (823.66 pt with Narrow margins unfolded, when the view and gap were
    /// shares of the screen) left every page's text up to a point right of
    /// where the layout put it, onto the hinge with Narrow margins
    /// (`docs/notes/layout-polish.md`, Text on the hinge). With a whole view
    /// and a whole gap, the page (the view less the gap) is whole too.
    ///
    /// foliate takes the gap as a percentage, and WebKit truncates lengths to
    /// 1/64 pt, so the percentage asks for this much more than the whole
    /// gap: a quarter of that step, which truncates back to the gap.
    static let wholePageGap = 1.0 / 256

    /// `gap` points of a `view` points wide, as foliate's percentage.
    private static func gapPercent(_ gap: Double, of view: Double, else fallback: Double) -> Double {
        view > 0 ? (gap + wholePageGap) / view * 100 : fallback
    }

    /// To WebKit's 1/64 pt, so a whole view between two insets stays whole.
    private static func snapped(_ value: Double) -> Double {
        (value * 64).rounded() / 64
    }

    /// The gap between the two pages in a reader `width` wide, as foliate lays
    /// it out (centred in its view, `gap`% of the view's width).
    func gap(inReaderWidth width: Double) -> ClosedRange<Double>? {
        guard columns == 2, let gapPercent else { return nil }
        let viewWidth = width - leftInset - rightInset
        let mid = leftInset + viewWidth / 2
        let half = gapPercent / 100 * viewWidth / 2
        return (mid - half)...(mid + half)
    }

    /// Where each page's text runs across a reader `width` wide, left to
    /// right, as `paginator.js` lays it out: a centred container
    /// `(1 - gap)` of the view wide, capped at `max-inline-size` per column,
    /// split into columns padded by half of foliate's gap each side. Below
    /// the cap the outer margins and the gutter all come out at `gap`% of
    /// the view. While foliate decides the columns (no fold: an iPhone, an
    /// iPad), its own choice for a reader `height` tall (`foliateColumns`);
    /// `nil` without one.
    func textColumns(inReaderWidth width: Double, height: Double? = nil) -> [ClosedRange<Double>]? {
        guard let columns = columns ?? height.map({ foliateColumns(width: width, height: $0) }), columns > 0 else { return nil }
        let count = Double(columns)
        let viewWidth = width - leftInset - rightInset
        let share = (gapPercent ?? Self.defaultGapPercent) / 100
        let container = min(viewWidth * (1 - share), (maxInlineSize ?? Self.defaultMaxInlineSize) * count)
        let gap = share / (1 - share) * container
        let columnWidth = container / count - gap
        guard columnWidth > 0 else { return nil }
        let containerLeft = leftInset + (viewWidth - container) / 2
        return (0..<columns).map { index in
            let start = containerLeft + Double(index) * container / count + gap / 2
            return start...(start + columnWidth)
        }
    }

    /// The columns foliate lays out when it decides them, as `paginator.js`
    /// does: one in a portrait view, otherwise as many `max-inline-size`
    /// columns as the text area needs, up to two.
    func foliateColumns(width: Double, height: Double) -> Int {
        let viewWidth = width - leftInset - rightInset
        guard viewWidth > height - topInset - bottomInset else { return 1 }
        let share = (gapPercent ?? Self.defaultGapPercent) / 100
        let column = maxInlineSize ?? Self.defaultMaxInlineSize
        let container = min(viewWidth * (1 - share), column * 2)
        return min(2, max(1, Int((container / column).rounded(.up))))
    }

    /// How far the bar and a panel keep from the safe area's sides and the
    /// fold.
    static let edgeInset = 12.0

    /// Where the progress bar goes in a reader of `geometry`: left to right,
    /// the stretches it covers, as wide as a panel whatever the margins (Adam,
    /// 2026-11-04). A panel can't follow the margins: it would resize under
    /// the finger choosing them. One stretch under the page or the spread; in
    /// book mode one under each page, so nothing sits on the hinge (decision
    /// 9). A spread's left edge mirrors the side column, as its text does.
    func barSpans(in geometry: ReaderGeometry, bookMode: Bool) -> [ClosedRange<Double>] {
        let safe = geometry.safeArea
        let spreadFold = columns == 2 ? fold : nil
        let left = (spreadFold == nil ? safe.left : max(safe.left, safe.right)) + Self.edgeInset
        let right = Double(geometry.size.width) - safe.right - Self.edgeInset
        if bookMode, let spreadFold {
            return [left...(spreadFold.lowerBound - Self.edgeInset), (spreadFold.upperBound + Self.edgeInset)...right]
        }
        return [left...max(left, right)]
    }

    /// The bar's bottom edge: just above the home indicator, so nothing runs
    /// under it, and 12 pt up from a screen without one.
    static func barBottom(in geometry: ReaderGeometry) -> Double {
        Double(geometry.size.height) - max(geometry.safeArea.bottom, edgeInset)
    }

    /// Arguments for `window.octavo.setLayout`.
    var scriptArguments: [String: Any] {
        [
            "columns": columns ?? NSNull(),
            "gapPercent": gapPercent ?? NSNull(),
            "maxInlineSize": maxInlineSize ?? NSNull(),
            "leftInset": leftInset,
            "rightInset": rightInset,
            "topInset": topInset,
            "bottomInset": bottomInset,
            "fold": fold.map { [$0.lowerBound, $0.upperBound] } ?? NSNull(),
        ]
    }
}
