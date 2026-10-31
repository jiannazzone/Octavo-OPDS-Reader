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

/// Where the reader view sits relative to the fold: its size, and the
/// hinge's `division` reserved regions in its own coordinates (not mirrored
/// for right-to-left, because the web page lays out in physical coordinates).
///
/// On iPhone Duo (iOS 27.1 simulator) the division region is the hinge line
/// plus 20pt margins each side, the full height of the screen. It's reported
/// only on the inner display, inactive when flat and active when half open.
nonisolated struct ReaderGeometry: Equatable, Sendable, Codable {
    nonisolated struct Region: Equatable, Sendable, Codable {
        /// Includes the margins the system asks interactive content to keep.
        var frame: CGRect
        var isActive: Bool
    }

    var size: CGSize
    var divisions: [Region] = []
}

/// How foliate-js lays out pages, decided from the posture and where the fold
/// runs through the reader. Applied by `bridge.js` `setLayout`.
///
/// foliate centres its column gap in the middle of the `foliate-view`, and
/// with equal spacing the gap is `gap`% of the view's width (the outer margins
/// match it). So a spread whose gap sits over the fold needs the view centred
/// on the fold (`leftInset`/`rightInset`) and a gap at least as wide as the
/// fold's region.
nonisolated struct ReaderLayout: Equatable, Sendable, Codable {
    /// Pages side by side. `nil` leaves it to foliate (two when the reader
    /// area is landscape and wide enough, else one).
    var columns: Int?
    /// foliate's `gap`, in percent of the view's width. `nil` = foliate's 7%.
    var gapPercent: Double?
    /// foliate's `max-inline-size` in CSS px. `nil` = foliate's 720px.
    var maxInlineSize: Double?
    /// CSS px trimmed off the `foliate-view`'s left and right edges.
    var leftInset: Double = 0
    var rightInset: Double = 0
    /// The fold's horizontal extent in the reader, when the gap is meant to
    /// cover it. Used only for checking where text lands.
    var fold: ClosedRange<Double>?

    /// foliate-js's default `gap`.
    static let defaultGapPercent = 7.0
    /// A page narrower than this either side of the fold isn't worth a spread.
    static let minimumPageWidth = 200.0

    /// Whatever foliate does on its own.
    static let automatic = ReaderLayout()
    /// One page, foliate's spacing.
    static let single = ReaderLayout(columns: 1)

    init(columns: Int? = nil, gapPercent: Double? = nil, maxInlineSize: Double? = nil,
         leftInset: Double = 0, rightInset: Double = 0, fold: ClosedRange<Double>? = nil) {
        self.columns = columns
        self.gapPercent = gapPercent
        self.maxInlineSize = maxInlineSize
        self.leftInset = leftInset
        self.rightInset = rightInset
        self.fold = fold
    }

    /// - Closed: one page.
    /// - Open or half open with a fold running top to bottom: two pages, the
    ///   gap over the fold. The region counts even when inactive (flat): the
    ///   crease is still there.
    /// - Open with the fold running across (device turned): one page. Whether
    ///   to do more there is a UI question.
    /// - Open without any region reported: two pages around the middle if
    ///   the reader is landscape, else one. (During an unfold the hinge
    ///   reports open a moment before the reader takes the inner display's
    ///   size.)
    /// - No hinge reported: a spread if an active fold is reported, otherwise
    ///   foliate decides.
    init(posture: ReaderPosture, geometry: ReaderGeometry?) {
        let size = geometry?.size ?? .zero
        let width = Double(size.width)
        switch posture {
        case .closed:
            self = .single
        case .open, .halfOpen:
            if let spine = geometry.flatMap({ Self.spine(in: $0, includeInactive: true) }) {
                self = .spread(width: width, fold: spine)
            } else if geometry?.divisions.isEmpty == false || size.width <= size.height
                        || width < 2 * Self.minimumPageWidth {
                self = .single
            } else {
                self = .spread(width: width, fold: nil)
            }
        case .noHinge:
            self = geometry.flatMap { Self.spine(in: $0, includeInactive: false) }
                .map { .spread(width: width, fold: $0) } ?? .automatic
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

    /// Two pages with foliate's view centred on `fold` (or on the middle) and
    /// a gap no narrower than the fold.
    static func spread(width: Double, fold: CGRect?) -> ReaderLayout {
        let mid = fold.map { Double($0.midX) } ?? width / 2
        let viewWidth = 2 * min(mid, width - mid)
        let foldWidth = Double(fold?.width ?? 0)
        // Rounded up to 0.1% so the gap never comes out narrower than the fold.
        let foldPercent = (foldWidth / viewWidth * 1000).rounded(.up) / 10
        return ReaderLayout(
            columns: 2,
            gapPercent: max(defaultGapPercent, foldPercent),
            // At half the view, foliate fits exactly two columns and never caps
            // the text width, which would move the gap off-centre.
            maxInlineSize: (viewWidth / 2).rounded(.up),
            leftInset: max(0, 2 * mid - width),
            rightInset: max(0, width - 2 * mid),
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

    /// Arguments for `window.octavo.setLayout`.
    var scriptArguments: [String: Any] {
        [
            "columns": columns ?? NSNull(),
            "gapPercent": gapPercent ?? NSNull(),
            "maxInlineSize": maxInlineSize ?? NSNull(),
            "leftInset": leftInset,
            "rightInset": rightInset,
            "fold": fold.map { [$0.lowerBound, $0.upperBound] } ?? NSNull(),
        ]
    }
}
