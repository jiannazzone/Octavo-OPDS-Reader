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

/// The margins setting (decision 8): foliate ties the outer margins and the
/// gutter between two pages together as its `gap`, a share of the page
/// area's width. Approved values 2026-11-01. The Customize panel (#18)
/// binds to `key`.
nonisolated enum ReaderMargins: String, CaseIterable, Sendable, Codable {
    /// Text reaches the side column's edge: the margin itself lies under
    /// the column. Unfolded, the gutter is the hinge's 40 pt.
    case narrow
    /// The frames (07–09): foliate's own 7%, 27 pt folded and 55 pt
    /// unfolded.
    case medium
    case wide

    static let key = "reader.margins"
    static let standard = ReaderMargins.medium

    /// foliate's `gap`, in percent of the page area's width.
    var gapPercent: Double {
        switch self {
        case .narrow: 4.6
        case .medium: 7
        case .wide: 10
        }
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
    init(posture: ReaderPosture, geometry: ReaderGeometry?, margins: ReaderMargins = .standard) {
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
    }

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

    /// One page across the safe area's width. With narrow margins the view
    /// reaches under each side's inset by its own margin, so the text meets
    /// the inset's edge.
    static func single(in geometry: ReaderGeometry, margins: ReaderMargins) -> ReaderLayout {
        let safe = geometry.safeArea
        let width = Double(geometry.size.width)
        let content = max(0, width - safe.left - safe.right)
        let gap = margins.gapPercent / 100
        var left = safe.left
        var right = safe.right
        if margins == .narrow {
            let sides = (safe.left > 0 ? 1.0 : 0) + (safe.right > 0 ? 1.0 : 0)
            let margin = gap * content / (1 - sides * gap)
            if safe.left > 0 { left = max(0, left - margin) }
            if safe.right > 0 { right = max(0, right - margin) }
        }
        return ReaderLayout(
            columns: 1, gapPercent: margins.gapPercent,
            leftInset: left, rightInset: right, topInset: safe.top, bottomInset: safe.bottom
        )
    }

    /// Two pages with foliate's view centred on `fold` (or on the middle of
    /// the safe area) and a gap no narrower than the fold. The view is as
    /// wide as the shorter side allows, so the margins match on both sides
    /// (unfolded, the left edge gives up what the side column takes on the
    /// right). Narrow margins reach under both edges by the margin.
    static func spread(in geometry: ReaderGeometry, fold: CGRect?, margins: ReaderMargins) -> ReaderLayout {
        let safe = geometry.safeArea
        let width = Double(geometry.size.width)
        let contentLeft = safe.left
        let contentRight = width - safe.right
        let mid = fold.map { Double($0.midX) } ?? (contentLeft + contentRight) / 2
        let half = max(0, min(mid - contentLeft, contentRight - mid))
        let foldWidth = Double(fold?.width ?? 0)
        let reaches = margins == .narrow
        // The view's width for a gap `g`, and the smallest `g` whose gutter
        // (g × view) covers the fold.
        let viewWidth = { (g: Double) in reaches ? 2 * half / (1 - 2 * g) : 2 * half }
        let foldShare = half > 0 ? (reaches ? foldWidth / (2 * half + 2 * foldWidth) : foldWidth / (2 * half)) : 0
        // Rounded up to 0.1% so the gap never comes out narrower than the fold.
        let gapPercent = max(margins.gapPercent, (foldShare * 1000).rounded(.up) / 10)
        let view = viewWidth(gapPercent / 100)
        return ReaderLayout(
            columns: 2,
            gapPercent: gapPercent,
            // At half the view, foliate fits exactly two columns and never caps
            // the text width, which would move the gap off-centre.
            maxInlineSize: (view / 2).rounded(.up),
            leftInset: max(0, mid - view / 2),
            rightInset: max(0, width - (mid + view / 2)),
            topInset: safe.top,
            bottomInset: safe.bottom,
            fold: fold.map { Double($0.minX)...Double($0.maxX) }
        )
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
    /// the view. `nil` while foliate decides the columns.
    func textColumns(inReaderWidth width: Double) -> [ClosedRange<Double>]? {
        guard let columns, columns > 0 else { return nil }
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
