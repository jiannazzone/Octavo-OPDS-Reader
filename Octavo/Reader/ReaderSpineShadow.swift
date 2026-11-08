import SwiftUI

/// The shadow in the spine of a book held half open (decision 9), drawn over
/// the gap between the two pages. It sits outside the book's content, so it
/// never touches the text or the book's own styles. Ignores touches.
///
/// Its own view, so a hinge report redraws only the shadow: the angle changes
/// many times a second while the hinge moves.
struct ReaderSpineShadow: View {
    let model: ReaderModel
    let theme: ReaderTheme

    var body: some View {
        if model.isBookMode, let page = model.geometry?.size,
           let gap = model.layout.gap(inReaderWidth: Double(page.width)) {
            let shade = ReaderSpineShade(angle: model.hingeAngle, theme: theme)
            let color = Color(hex: shade.color)
            LinearGradient(
                stops: shade.stops.map { .init(color: color.opacity($0.opacity), location: $0.location) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: gap.upperBound - gap.lowerBound, height: page.height)
            .offset(x: gap.lowerBound)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// How the spine shadow looks at a hinge angle on a theme (Adam,
/// 2026-11-07): it deepens and widens as the book closes, from nothing at
/// `BookModeThresholds.flat` to its darkest at `lowestEntry` and below, and
/// stays within the gap. Each theme has its own colour and depth.
nonisolated struct ReaderSpineShade: Equatable, Sendable {
    nonisolated struct Stop: Equatable, Sendable {
        /// Across the gap, 0 at its left edge and 1 at its right.
        var location: Double
        var opacity: Double
    }

    /// `#rrggbb`.
    var color: String
    /// Darkest at the fold, clear at the gap's edges.
    var stops: [Stop]

    /// How closed the book is, 0 at `flat` and 1 at `lowestEntry` or below.
    /// Without an angle, as at 90°.
    static func closing(angle: Double?, thresholds: BookModeThresholds = .standard) -> Double {
        let angle = angle ?? 90
        let closing = (thresholds.flat - angle) / (thresholds.flat - thresholds.lowestEntry)
        return min(max(closing, 0), 1)
    }

    init(angle: Double?, theme: ReaderTheme, thresholds: BookModeThresholds = .standard) {
        let closing = Self.closing(angle: angle, thresholds: thresholds)
        let peak = theme.spineShadow.deepest * closing
        // Near flat the shadow keeps to the fold; closed it fills the gap.
        let falloff = 2.4 - 1.2 * closing
        color = theme.spineShadow.color
        stops = (0...Self.steps).map { step in
            let location = Double(step) / Double(Self.steps)
            let fromFold = abs(location - 0.5) * 2
            return Stop(location: location, opacity: peak * pow(1 - fromFold, falloff))
        }
    }

    /// Stops across the gap, enough for the curve to look smooth.
    private static let steps = 16

    /// The darkest the shadow gets at the fold.
    var peak: Double { stops.map(\.opacity).max() ?? 0 }
}

nonisolated extension ReaderTheme {
    /// The spine shadow's colour, and its opacity at the fold when the book
    /// is closed as far as book mode goes. Warm on Paper and Sepia, as a
    /// shadow on cream paper is; deeper on Night, where black over the dark
    /// page shows less.
    var spineShadow: SpineShadow {
        switch self {
        case .original: SpineShadow(color: "#000000", deepest: 0.32)
        case .paper: SpineShadow(color: "#3d2e17", deepest: 0.38)
        case .sepia: SpineShadow(color: "#4a3112", deepest: 0.4)
        case .night: SpineShadow(color: "#000000", deepest: 0.7)
        }
    }

    struct SpineShadow: Equatable, Sendable {
        /// `#rrggbb`.
        var color: String
        var deepest: Double
    }
}
