import SwiftUI

/// A page turn on screen (decision 27): pictures of the page before and
/// after, drawn over the web view while foliate turns underneath.
/// `ReaderModel` drives it; `ReaderTurnBase` draws what lies still and
/// `ReaderTurnLeaf` what moves, with the spine shadow between them.
///
/// The pictures are the web view's alone, so each page's footer is drawn
/// with them from its place (the live footer hides during a turn). Where
/// the new page isn't drawn yet (a chapter still loading), the page's
/// colour shows, and the page fades in when it comes.
struct ReaderTurn: Equatable {
    /// A snapshot view can be in one place only, so each half that's drawn
    /// has its own.
    struct Pictures: Equatable {
        var left: ReaderSnapshot?
        var right: ReaderSnapshot?
        var whole: ReaderSnapshot?

        /// One half of a spread, or the whole page.
        subscript(half: ReaderTurnSide?) -> ReaderSnapshot? {
            switch half {
            case .left: left
            case .right: right
            case nil: whole
            }
        }
    }

    let id: Int
    let motion: ReaderTurnMotion
    let side: ReaderTurnSide
    let geometry: ReaderGeometry
    let layout: ReaderLayout
    /// Where a flipped spread's pages meet: the middle of foliate's gap.
    /// `nil` for one page, which flips about its left edge.
    let spine: Double?
    /// The page's colour.
    let paper: Color
    /// 0 as the turn starts, 1 when the new page lies flat.
    var progress = 0.0
    let old: Pictures
    let oldPlace: ReaderPlace
    /// Once foliate has drawn the new page.
    var new: Pictures?
    var newPlace: ReaderPlace?

    var size: CGSize { geometry.size }

    /// How wide the page that moves is: half a flipped spread, else the
    /// whole page (a slide moves both pages of a spread together).
    var pageWidth: Double {
        let width = Double(size.width)
        guard motion == .flip, let spine else { return width }
        return side == .right ? width - spine : spine
    }

    /// The pictures a turn needs before it starts, and once the new page is
    /// drawn, in the page's coordinates. A flip needs the new page only where
    /// it's on the back of the turning page; elsewhere the web view shows it.
    nonisolated static func regions(motion: ReaderTurnMotion, side: ReaderTurnSide, size: CGSize, spine: Double?) -> (old: Regions, new: Regions) {
        switch motion {
        case .slide:
            return (.whole, .whole)
        case .fade, .none:
            return (.whole, [])
        case .flip:
            guard spine != nil else { return (.whole, side == .left ? .whole : []) }
            return ([.left, .right], side == .right ? .left : .right)
        }
    }

    nonisolated struct Regions: OptionSet, Sendable {
        let rawValue: Int
        static let whole = Regions(rawValue: 1)
        static let left = Regions(rawValue: 2)
        static let right = Regions(rawValue: 4)
    }

    /// The halves of a spread split at `spine`, in the page's coordinates.
    nonisolated static func half(_ side: ReaderTurnSide, of size: CGSize, spine: Double) -> CGRect {
        side == .left
            ? CGRect(x: 0, y: 0, width: spine, height: size.height)
            : CGRect(x: spine, y: 0, width: Double(size.width) - spine, height: size.height)
    }
}

/// What lies still under a turn: under a flip, the half the page lands on
/// (still the old page) and the page it uncovers (the web view, with its
/// footer). Under the spine shadow and the turning page.
struct ReaderTurnBase: View {
    let turn: ReaderTurn

    var body: some View {
        ZStack(alignment: .topLeading) {
            if turn.motion == .flip {
                if let spine = turn.spine {
                    let landing = ReaderTurnPage.half(turn.side.opposite, of: turn.size, spine: spine)
                    ReaderTurnPage(turn: turn, picture: turn.old[turn.side.opposite], place: turn.oldPlace)
                        .clipShape(ReaderTurnRegion(rect: landing))
                    ReaderTurnUncovered(turn: turn)
                        .clipShape(ReaderTurnRegion(rect: ReaderTurnPage.half(turn.side, of: turn.size, spine: spine)))
                } else if turn.side == .right {
                    ReaderTurnUncovered(turn: turn)
                } else {
                    // Back on one page: the page before comes over this one.
                    ReaderTurnPage(turn: turn, picture: turn.old.whole, place: turn.oldPlace)
                }
            }
        }
        .frame(width: turn.size.width, height: turn.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What moves: the slide's two pages, the fading old page, or the page
/// that flips, with the next page on its back.
struct ReaderTurnLeaf: View, Animatable {
    let turn: ReaderTurn
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Group {
            switch turn.motion {
            case .slide: slide
            case .fade: fade
            case .flip: flip
            case .none: EmptyView()
            }
        }
        .frame(width: turn.size.width, height: turn.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Slide

    /// Both pages move together, the new one coming in from the side the
    /// finger leaves.
    private var slide: some View {
        let width = Double(turn.size.width)
        let shift = progress * width * (turn.side == .right ? -1 : 1)
        return ZStack(alignment: .topLeading) {
            ReaderTurnPage(turn: turn, picture: turn.old.whole, place: turn.oldPlace)
                .offset(x: shift)
            ReaderTurnIncoming(turn: turn, half: nil)
                .offset(x: shift + (turn.side == .right ? width : -width))
        }
        .clipped()
    }

    // MARK: Fade

    /// The old page fades into the web view's new one.
    private var fade: some View {
        ZStack(alignment: .topLeading) {
            if let newPlace = turn.newPlace {
                ReaderFooterLines(place: newPlace, layout: turn.layout, geometry: turn.geometry)
                    .opacity(progress)
            }
            ReaderTurnPage(turn: turn, picture: turn.old.whole, place: turn.oldPlace)
                .opacity(1 - progress)
        }
    }

    // MARK: Flip

    /// The page swings over its hinge (the spine, or one page's left edge)
    /// like paper. Past halfway its back shows, which is the page it lands
    /// as, drawn mirrored so the swing shows it the right way round.
    private var flip: some View {
        let width = Double(turn.size.width)
        let hinge = turn.spine ?? 0
        // One page going back: the page before comes over from the left, the
        // forward swing played backwards.
        let comesBack = turn.spine == nil && turn.side == .left
        let angle = (comesBack ? 1 - progress : progress) * 180
        let showsFront = angle <= 90
        let leafRect = turn.spine.map { ReaderTurnPage.half(turn.side, of: turn.size, spine: $0) }
            ?? CGRect(origin: .zero, size: turn.size)
        let anchor = UnitPoint(x: width > 0 ? hinge / width : 0, y: 0.5)
        // Forward, the right edge rises and goes left over the hinge.
        let direction: Double = (turn.spine != nil && turn.side == .left) ? 1 : -1
        return ZStack(alignment: .topLeading) {
            if showsFront {
                front
            } else {
                back
                    .scaleEffect(x: -1, y: 1, anchor: anchor)
            }
            // Darker as it stands up from the page.
            Color.black
                .opacity(0.18 * sin(angle * .pi / 180))
        }
        .clipShape(ReaderTurnRegion(rect: leafRect))
        .rotation3DEffect(.degrees(direction * angle), axis: (x: 0, y: 1, z: 0), anchor: anchor, perspective: 0.35)
    }

    /// The face that starts up: the old page, or, coming back on one page,
    /// the page before.
    @ViewBuilder private var front: some View {
        if turn.spine == nil {
            if turn.side == .left {
                ReaderTurnIncoming(turn: turn, half: nil)
            } else {
                ReaderTurnPage(turn: turn, picture: turn.old.whole, place: turn.oldPlace)
            }
        } else {
            ReaderTurnPage(turn: turn, picture: turn.old[turn.side], place: turn.oldPlace)
        }
    }

    /// The back: the new page it lands as on a spread; plain paper on one page.
    @ViewBuilder private var back: some View {
        if turn.spine != nil {
            ReaderTurnIncoming(turn: turn, half: turn.side.opposite)
        } else {
            turn.paper
        }
    }
}

/// The new page as far as it's known: the page's colour until foliate has
/// drawn it, then its picture (one half of a spread, or all of it), faded
/// in, with its footer.
private struct ReaderTurnIncoming: View {
    let turn: ReaderTurn
    let half: ReaderTurnSide?

    var body: some View {
        ZStack(alignment: .topLeading) {
            turn.paper
            if let new = turn.new, let place = turn.newPlace {
                ReaderTurnPage(turn: turn, picture: new[half], place: place)
                    .transition(.opacity)
            }
        }
        .frame(width: turn.size.width, height: turn.size.height, alignment: .topLeading)
    }
}

/// The page a turn uncovers: the web view itself, which already shows it,
/// under the page's colour until it's drawn.
private struct ReaderTurnUncovered: View {
    let turn: ReaderTurn

    var body: some View {
        ZStack(alignment: .topLeading) {
            if turn.new == nil {
                turn.paper
                    .transition(.opacity)
            }
            if let place = turn.newPlace {
                ReaderFooterLines(place: place, layout: turn.layout, geometry: turn.geometry)
            }
        }
        .frame(width: turn.size.width, height: turn.size.height, alignment: .topLeading)
    }
}

/// A page as it was: its picture where it was taken, on the page's colour,
/// with its footer. As big as the reader.
struct ReaderTurnPage: View {
    let turn: ReaderTurn
    let picture: ReaderSnapshot?
    let place: ReaderPlace

    var body: some View {
        ZStack(alignment: .topLeading) {
            turn.paper
            if let picture {
                ReaderSnapshotView(snapshot: picture)
                    .frame(width: picture.frame.width, height: picture.frame.height)
                    .offset(x: picture.frame.minX, y: picture.frame.minY)
            }
            ReaderFooterLines(place: place, layout: turn.layout, geometry: turn.geometry)
        }
        .frame(width: turn.size.width, height: turn.size.height, alignment: .topLeading)
    }

    static func half(_ side: ReaderTurnSide, of size: CGSize, spine: Double) -> CGRect {
        ReaderTurn.half(side, of: size, spine: spine)
    }
}

/// A rectangle in the reader's coordinates, to clip a whole-page view to.
nonisolated struct ReaderTurnRegion: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        Path(rect)
    }
}
