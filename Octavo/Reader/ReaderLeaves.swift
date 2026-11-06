import SwiftUI

/// Leafing through to your place (Adam, 2026-11-06): past page 1, a few leaves
/// go over before your page lands, more the further in you are. They're drawn,
/// faint grey lines on the page's colour, and only the last carries your real
/// page on its back, so the reader never moves to capture earlier pages.
/// `ReaderCoverMotion` plays them and `ReaderLeavesView` draws them.
///
/// Unfolded and half open each flips over the spine. Folded each swings off
/// the left edge, as the cover does. After a cover they start while it's still
/// swinging; unfolding on a cover there's none, and they start at once.
nonisolated struct ReaderLeaves: Equatable, Sendable {
    let count: Int
    /// Over the spine, or folded, off the left edge.
    let spread: Bool
    /// Starts part way through the cover's swing.
    let followsCover: Bool
    /// Seconds the last leaf has waited for your page, which goes on its back.
    var lastLeafWait = 0.0

    /// Seconds between one leaf starting and the next.
    static let gap = 0.07

    /// 2 near the start of the book, 5 near the end.
    static func count(progress: Double) -> Int {
        2 + Int((min(max(progress, 0), 1) * 3).rounded())
    }

    /// Not on page 1, with Reduce Motion, or with Page Turn on Fade or None.
    static func play(fraction: Double, pageTurn: ReaderPageTurn, reduceMotion: Bool) -> Bool {
        fraction > 0 && !reduceMotion && pageTurn != .fade && pageTurn != .none
    }

    /// Seconds each leaf takes to go over.
    var duration: Double { spread ? 0.3 : 0.15 }

    /// Seconds from the start of the cover's swing, if there is one.
    func start(of leaf: Int) -> Double {
        let first = !followsCover ? 0 : spread ? 0.2 : 0.1
        return first + Double(leaf) * Self.gap + (leaf == count - 1 ? lastLeafWait : 0)
    }

    /// When the last leaf has gone over.
    var end: Double { start(of: count - 1) + duration }

    /// Degrees: 0 flat where it starts, 180 flat over the spine or, folded, 90
    /// edge on at the left edge.
    func angle(of leaf: Int, at time: Double) -> Double {
        let elapsed = min(max((time - start(of: leaf)) / duration, 0), 1)
        return spread ? UnitCurve.easeInOut.value(at: elapsed) * 180 : UnitCurve.easeIn.value(at: elapsed) * 90
    }

    /// The leaves worth drawing at `time`: those moving, the next one waiting
    /// under them, and unfolded the last to land. Folded, a leaf that's gone
    /// has gone.
    func shown(at time: Double) -> Range<Int> {
        let landed = (0..<count).last { time >= start(of: $0) + duration }
        let waiting = (0..<count).first { time < start(of: $0) }
        let first = landed.map { spread ? $0 : $0 + 1 } ?? 0
        let last = waiting.map { $0 + 1 } ?? count
        return min(first, last)..<last
    }
}

/// What the lines follow, so they sit about where the book's text will.
nonisolated struct ReaderLeafStyle: Equatable, Sendable {
    /// Points from one line to the next: a book's own at 100%, as measured on
    /// the sample book.
    var pitch = 20.0
    var margins = ReaderMargins.standard

    init(appearance: ReaderAppearance = ReaderAppearance(), margins: ReaderMargins = .standard) {
        pitch = 20 * appearance.textScale * (appearance.lineSpacing.map { $0 / 1.25 } ?? 1)
        self.margins = margins
    }
}

/// The lines on a leaf, in the window's coordinates: rows across each column
/// of `layout`, with a short line now and then to end a paragraph. A leaf shows
/// the half it's clipped to. `seed` makes one leaf differ from the next.
nonisolated enum ReaderLeafLines {
    static func path(layout: ReaderLayout, size: CGSize, pitch: Double, seed: Int) -> Path {
        var path = Path()
        guard pitch > 0, let columns = layout.textColumns(inReaderWidth: Double(size.width)) else { return path }
        let top = layout.topInset + ReaderLayout.verticalMargin
        let bottom = Double(size.height) - layout.bottomInset - ReaderLayout.verticalMargin
        let height = pitch * 0.3
        var random = seed &* 7_919 &+ 17
        func next(_ range: Int) -> Int {
            random = (random &* 1_103_515_245 &+ 12_345) & 0x7FFF_FFFF
            return (random >> 8) % range
        }
        for column in columns {
            let width = column.upperBound - column.lowerBound
            var indent = 0.0
            var y = top + (pitch - height) / 2
            while y + height <= bottom {
                let endsParagraph = next(7) == 0
                let length = endsParagraph ? width * (0.3 + Double(next(50)) / 100) : width - indent
                path.addRoundedRect(
                    in: CGRect(x: column.lowerBound + indent, y: y, width: max(length, 0), height: height),
                    cornerSize: CGSize(width: height / 2, height: height / 2)
                )
                indent = endsParagraph ? pitch * 0.8 : 0
                y += pitch
            }
        }
        return path
    }
}

private nonisolated struct ReaderLeafLinesShape: Shape {
    let lines: Path

    func path(in _: CGRect) -> Path { lines }
}

/// A plain leaf, as big as the window: the page's colour and its lines.
struct ReaderLeafFace: View {
    let motion: ReaderCoverMotion
    let variant: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            motion.paper
            if !motion.leafLines.isEmpty {
                ReaderLeafLinesShape(lines: motion.leafLines[variant % motion.leafLines.count])
                    .fill(Color.gray.opacity(0.22))
            }
        }
        .frame(width: motion.windowSize.width, height: motion.windowSize.height, alignment: .topLeading)
    }
}

/// The leaves going over. On the right of the spine an earlier leaf lies over a
/// later one; on the left a later one lands on top of it.
struct ReaderLeavesView: View {
    let motion: ReaderCoverMotion
    let leaves: ReaderLeaves

    var body: some View {
        let time = motion.clock
        ZStack(alignment: .topLeading) {
            ForEach(leaves.shown(at: time), id: \.self) { leaf in
                let angle = leaves.angle(of: leaf, at: time)
                ReaderLeafView(motion: motion, leaf: leaf, isLast: leaf == leaves.count - 1, angle: angle)
                    .zIndex(angle <= 90 ? -Double(leaf) : Double(leaf))
            }
        }
        .frame(width: motion.windowSize.width, height: motion.windowSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// One leaf, swung over its hinge like the cover and a page's flip.
private struct ReaderLeafView: View {
    let motion: ReaderCoverMotion
    let leaf: Int
    let isLast: Bool
    let angle: Double

    var body: some View {
        let width = Double(motion.windowSize.width)
        let hinge = motion.spread ? motion.spine : 0
        let anchor = UnitPoint(x: width > 0 ? hinge / width : 0, y: 0.5)
        return ZStack(alignment: .topLeading) {
            if angle <= 90 {
                ReaderLeafFace(motion: motion, variant: leaf + 1)
            } else {
                back
                    .scaleEffect(x: -1, y: 1, anchor: anchor)
            }
            Color.black
                .opacity(0.18 * sin(angle * .pi / 180))
        }
        .frame(width: motion.windowSize.width, height: motion.windowSize.height, alignment: .topLeading)
        .clipShape(ReaderTurnRegion(rect: motion.leafFrame))
        .rotation3DEffect(.degrees(-angle), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.35)
    }

    /// The left page it lands as: your real one on the last leaf.
    @ViewBuilder private var back: some View {
        if isLast, let left = motion.pages?.left {
            ZStack(alignment: .topLeading) {
                motion.paper
                ReaderSnapshotView(snapshot: left)
                    .frame(width: left.frame.width, height: left.frame.height)
                    .offset(x: left.frame.minX, y: left.frame.minY)
            }
            .frame(width: motion.windowSize.width, height: motion.windowSize.height, alignment: .topLeading)
        } else {
            ReaderLeafFace(motion: motion, variant: leaf)
        }
    }
}
