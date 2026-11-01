import Foundation

/// Where book mode starts and ends, in degrees of hinge angle (decision 9).
///
/// - Important: The design's numbers, checked only on the iPhone Duo
///   simulator, which reports angles in steps of about 3.3°. Set the final
///   numbers on a real device.
nonisolated struct BookModeThresholds: Equatable, Sendable {
    /// Opening from the outer display, book mode starts here.
    var lowestEntry = 60.0
    /// Closing from flat, book mode starts here.
    var highestEntry = 150.0
    /// Opening this far or more lays the reader flat again. Between
    /// `highestEntry` and this, the mode stays as it was, so it doesn't
    /// flicker at the boundary.
    var flat = 160.0

    static let standard = BookModeThresholds()
}

/// The hinge as the reader tracks it: the posture (from the hinge's status)
/// and whether the reader is in book mode (from its angle).
///
/// `onHingeChange` repeats unchanged values many times a second while the
/// hinge settles, so `update` reports what actually changed, and nothing
/// for a repeat.
nonisolated struct ReaderHinge: Equatable, Sendable {
    nonisolated struct Change: OptionSet, Sendable {
        let rawValue: Int
        static let posture = Change(rawValue: 1)
        static let angle = Change(rawValue: 2)
        static let bookMode = Change(rawValue: 4)
    }

    private(set) var posture: ReaderPosture = .noHinge
    /// Degrees, 0 closed to 180 flat.
    private(set) var angle: Double?
    /// Half open like a book: page turns by halves, a spine shadow, and the
    /// controls in the side column.
    private(set) var isBookMode = false
    var thresholds = BookModeThresholds.standard

    mutating func update(posture: ReaderPosture, angle: Double?) -> Change {
        var change: Change = []
        if posture != self.posture {
            self.posture = posture
            change.insert(.posture)
        }
        if angle != self.angle {
            self.angle = angle
            change.insert(.angle)
        }
        let bookMode = Self.bookMode(after: isBookMode, posture: posture, angle: angle, thresholds: thresholds)
        if bookMode != isBookMode {
            isBookMode = bookMode
            change.insert(.bookMode)
        }
        return change
    }

    /// Book mode from `lowestEntry` to `highestEntry`, flat from `flat` up.
    /// Once in book mode, the reader stays there until it lies flat or
    /// folds: closing past `lowestEntry` towards the outer display doesn't
    /// leave it.
    static func bookMode(after current: Bool, posture: ReaderPosture, angle: Double?, thresholds: BookModeThresholds) -> Bool {
        guard posture == .halfOpen || posture == .open, let angle else { return false }
        if current { return angle < thresholds.flat }
        return angle >= thresholds.lowestEntry && angle <= thresholds.highestEntry
    }
}

/// How taps on the page behave, applied by `bridge.js` `setTapMode`.
nonisolated struct ReaderTapMode: Equatable, Sendable {
    /// Book mode: each half of the spread turns its way. Otherwise the outer
    /// sides turn pages and the middle shows the controls.
    var isBook = false
    /// Where the side column starts, in the page's coordinates. The page
    /// runs under it (decision 8); in book mode a tap there shows the
    /// controls, flat it counts as the right side.
    var columnStart: Double?
    /// The page's left and right edges outside the system's areas. The side
    /// zones are measured within it. `nil`: the whole page.
    var content: ClosedRange<Double>?
    /// The controls cover the page: any tap hides them instead of turning.
    var dismisses = false

    var scriptArguments: [String: Any] {
        [
            "book": isBook,
            "columnStart": columnStart ?? NSNull(),
            "content": content.map { [$0.lowerBound, $0.upperBound] } ?? NSNull(),
            "dismisses": dismisses,
        ]
    }
}
