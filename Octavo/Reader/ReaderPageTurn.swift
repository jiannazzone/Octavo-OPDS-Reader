import Foundation

/// Page Turn in Customize (decision 27): how a page turns. Kept in
/// `UserDefaults` with the other reading settings (decision 14).
nonisolated enum ReaderPageTurn: String, CaseIterable, Identifiable, Sendable, Codable {
    /// Slide on one page, flip on a spread; fade with Reduce Motion.
    case automatic
    case slide
    case flip
    case fade
    /// The instant turn Octavo had before, swipes dragging the page as
    /// foliate's paginator does.
    case none

    static let key = "reader.pageTurn"
    static let standard = ReaderPageTurn.automatic

    var id: Self { self }

    var name: String {
        switch self {
        case .automatic: "Automatic"
        case .slide: "Slide"
        case .flip: "Flip"
        case .fade: "Fade"
        case .none: "None"
        }
    }

    /// The motion for a turn. Automatic slides one page (folded, or one
    /// column across the fold turned sideways) and flips a spread over its
    /// spine; with Reduce Motion it fades. A style picked by hand applies in
    /// every posture, Reduce Motion or not.
    func motion(spread: Bool, reduceMotion: Bool) -> ReaderTurnMotion {
        switch self {
        case .automatic: reduceMotion ? .fade : spread ? .flip : .slide
        case .slide: .slide
        case .flip: .flip
        case .fade: .fade
        case .none: .none
        }
    }

    /// How a page shows that it turns without turning (the tour's Turn the
    /// page), if it can: a flip or a slide, started and let fall back. Reduce
    /// Motion holds it still, whatever style was picked.
    func hintMotion(spread: Bool, reduceMotion: Bool) -> ReaderTurnMotion? {
        guard !reduceMotion else { return nil }
        let motion = motion(spread: spread, reduceMotion: false)
        return motion == .flip || motion == .slide ? motion : nil
    }

    /// Whether Swift draws the turns. With None the page turns itself
    /// (`bridge.js` `setTurnMode`).
    var isAnimated: Bool { self != .none }
}

nonisolated enum ReaderTurnMotion: String, Equatable, Sendable {
    case slide
    case flip
    case fade
    case none

    /// Seconds for a whole turn (decision 27; set on a real Duo).
    var duration: Double {
        switch self {
        case .slide: 0.3
        case .flip: 0.5
        case .fade: 0.15
        case .none: 0
        }
    }
}

/// Which way a page goes, physically: `.right` is the right-hand page
/// lifting and going left (forward in a left-to-right book), `.left` the
/// left-hand page going right. A right-to-left book turns forward to the
/// left.
nonisolated enum ReaderTurnSide: String, Equatable, Sendable, Codable {
    case left
    case right

    var opposite: ReaderTurnSide { self == .left ? .right : .left }
}

/// A finger turning the page, as `ReaderSwipeRecognizer` reports it.
nonisolated struct ReaderTurnSwipe: Equatable, Sendable {
    nonisolated enum Phase: String, Sendable {
        /// The finger has moved far enough sideways: a turn to `side`.
        case began
        case changed
        /// Lifted: `velocity` decides with how far the turn has gone.
        case ended
        /// Taken away (the system took the touch): the page falls back.
        case cancelled
    }

    var phase: Phase
    /// Which way the turn goes; sent with `began`.
    var side: ReaderTurnSide?
    /// Points the finger has moved sideways since it landed, negative
    /// leftwards.
    var dx: Double = 0
    /// Points per millisecond as it lifted, negative leftwards.
    var velocity: Double = 0
}

/// A turn under a finger (decision 27): how far it has gone, and whether
/// letting go finishes it or lets the page fall back.
nonisolated enum ReaderTurnDrag {
    /// Points per millisecond: a faster flick decides by its direction alone.
    static let flickSpeed = 0.35

    /// How far a turn to `side` has gone (0...1) once the finger has moved
    /// `dx` points sideways (negative is leftwards) over pages `pageWidth`
    /// wide. A slide or a fade follows the finger point for point. A flip
    /// keeps the turning page's edge under the finger: the edge of a page
    /// turned by `t` sits `pageWidth × (1 - cos πt)` from where it started.
    static func progress(dx: Double, side: ReaderTurnSide, motion: ReaderTurnMotion, pageWidth: Double) -> Double {
        guard pageWidth > 0 else { return 0 }
        let travel = side == .right ? -dx : dx
        guard travel > 0 else { return 0 }
        switch motion {
        case .flip:
            let cosine = 1 - min(travel / pageWidth, 2)
            return acos(cosine) / .pi
        case .slide, .fade, .none:
            return min(travel / pageWidth, 1)
        }
    }

    /// Letting go after a turn to `side` has gone `progress`, the finger
    /// moving at `velocity` points per millisecond (negative is leftwards):
    /// a flick goes the way it points; otherwise past halfway finishes the
    /// turn and before halfway the page falls back.
    static func finishes(progress: Double, velocity: Double, side: ReaderTurnSide) -> Bool {
        let speed = side == .right ? -velocity : velocity
        if abs(speed) >= flickSpeed { return speed > 0 }
        return progress >= 0.5
    }

    /// Seconds to play the rest of a turn from `progress` to `target`, at
    /// the turn's own pace, but never so short it looks like a jump.
    static func remainingDuration(from progress: Double, to target: Double, motion: ReaderTurnMotion) -> Double {
        let rest = abs(target - progress)
        return max(motion.duration * rest, min(motion.duration, 0.12))
    }
}
