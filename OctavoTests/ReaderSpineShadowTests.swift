import Foundation
import Testing
@testable import Octavo

/// The spine shadow follows the hinge angle and the theme (decision 9).
struct ReaderSpineShadowTests {
    @Test(arguments: [(180.0, 0.0), (160, 0), (150, 0.1), (110, 0.5), (60, 1), (33.3, 1)])
    func closingRunsFromFlatToTheLowestEntry(angle: Double, closing: Double) {
        #expect(abs(ReaderSpineShade.closing(angle: angle) - closing) < 1e-9)
    }

    @Test func withoutAnAngleItLooksAsAtNinetyDegrees() {
        #expect(ReaderSpineShade(angle: nil, theme: .sepia) == ReaderSpineShade(angle: 90, theme: .sepia))
    }

    /// Book mode ends at 160° opening, so the shadow is gone by then and
    /// leaving book mode doesn't make it jump.
    @Test(arguments: ReaderTheme.allCases)
    func nothingAtFlat(theme: ReaderTheme) {
        #expect(ReaderSpineShade(angle: 160, theme: theme).peak == 0)
    }

    @Test(arguments: ReaderTheme.allCases)
    func deepensAsTheBookCloses(theme: ReaderTheme) {
        let peaks = [150.0, 120, 90, 60].map { ReaderSpineShade(angle: $0, theme: theme).peak }
        #expect(peaks == peaks.sorted() && Set(peaks).count == peaks.count)
        #expect(abs(peaks[3] - theme.spineShadow.deepest) < 1e-9)
        #expect(ReaderSpineShade(angle: 40, theme: theme) == ReaderSpineShade(angle: 60, theme: theme))
    }

    /// It fills more of the gap as the book closes: away from the fold it's
    /// a larger share of the darkest.
    @Test func widensAsTheBookCloses() {
        func share(at angle: Double) -> Double {
            let shade = ReaderSpineShade(angle: angle, theme: .original)
            let quarter = shade.stops.first { $0.location == 0.25 }
            return (quarter?.opacity ?? 0) / shade.peak
        }
        #expect(share(at: 60) > share(at: 90))
        #expect(share(at: 90) > share(at: 150))
    }

    /// Clear at the gap's edges, where the text starts, darkest at the fold,
    /// the same on both sides.
    @Test(arguments: ReaderTheme.allCases, [150.0, 90, 60])
    func staysWithinTheGap(theme: ReaderTheme, angle: Double) {
        let stops = ReaderSpineShade(angle: angle, theme: theme).stops
        #expect(stops.first?.location == 0 && stops.last?.location == 1)
        #expect(stops.first?.opacity == 0 && stops.last?.opacity == 0)
        #expect(stops.map(\.opacity) == stops.reversed().map(\.opacity))
        let fold = stops.first { $0.location == 0.5 }
        #expect(fold?.opacity == stops.map(\.opacity).max())
    }

    @Test func nightIsTheDeepest() {
        let others = [ReaderTheme.original, .paper, .sepia].map { ReaderSpineShade(angle: 90, theme: $0).peak }
        #expect(ReaderSpineShade(angle: 90, theme: .night).peak > others.max() ?? 0)
    }

    /// Warm on the cream themes, black on white and on Night.
    @Test func paperAndSepiaAreWarm() {
        for theme in [ReaderTheme.paper, .sepia] {
            let rgb = Self.rgb(theme.spineShadow.color)
            #expect(rgb.red > rgb.green && rgb.green > rgb.blue)
        }
        #expect(ReaderTheme.original.spineShadow.color == "#000000")
        #expect(ReaderTheme.night.spineShadow.color == "#000000")
    }

    private static func rgb(_ hex: String) -> (red: Int, green: Int, blue: Int) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }
}
