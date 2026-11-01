import Foundation

/// Gathers a fold's inputs into one re-layout (design decision 11).
///
/// A fold sends its inputs one at a time: the hinge (on iPhone Duo about
/// 200 ms before the scene moves to the other display), the reader's new
/// size, the fold region (briefly wrong on the way), then the page's own
/// resize. Laid out as they arrive, that's 4–5 renders and 11–13
/// relocations per fold, with wrong layouts on screen in between
/// (`docs/notes/duo-spreads.md` §5, re-measured for #5).
///
/// Instead, the hinge moving between folded and unfolded starts a batch: the
/// page keeps its size (`bridge.js` `hold`), and the layout waits until the
/// page has resized and the inputs have gone quiet, or until `maxWait`. A
/// hinge that moves back before the page has resized ends the batch at once:
/// nothing changed.
nonisolated struct FoldBatch: Equatable, Sendable {
    typealias Instant = ContinuousClock.Instant

    /// - Important: Measured on the iPhone Duo simulator only. Tune on a
    ///   real device.
    nonisolated struct Timing: Equatable, Sendable {
        /// How long the inputs must stay quiet once the page has resized.
        /// The simulator's fold region settles within about 10 ms of the
        /// page's resize.
        var quiet: Duration = .milliseconds(120)
        /// Lays out anyway after this long, in case the page never resizes
        /// (a display that doesn't change). On the Duo the page always
        /// resizes, so this only has to outlast a slow move: the simulator's
        /// page resized 0.1–3.5 s after the hinge, depending on load.
        var maxWait: Duration = .milliseconds(5000)
    }

    /// When the hinge last moved across.
    private(set) var startedAt: Instant
    private(set) var lastInputAt: Instant
    /// Whether the reader was folded before the hinge first moved.
    let wasFolded: Bool
    private(set) var isFolded: Bool
    /// The page has reported a new size since the hinge last moved.
    private(set) var pageResized = false
    /// The page has reported a new size since the batch started.
    private(set) var pageEverResized = false

    /// The hinge moved across, to `folded`.
    init(folded: Bool, at now: Instant) {
        startedAt = now
        lastInputAt = now
        wasFolded = !folded
        isFolded = folded
    }

    /// The hinge moved across again before the batch ended: wait for this
    /// move's resize too, unless it's back where it started.
    mutating func hingeMoved(folded: Bool, at now: Instant) {
        startedAt = now
        lastInputAt = now
        isFolded = folded
        pageResized = false
    }

    /// The hinge, the reader's size or the fold region changed.
    mutating func input(at now: Instant) {
        lastInputAt = max(lastInputAt, now)
    }

    /// The page reported its new size.
    mutating func pageResized(at now: Instant) {
        pageResized = true
        pageEverResized = true
        input(at: now)
    }

    /// When to lay out, if nothing else arrives.
    func deadline(_ timing: Timing) -> Instant {
        // Moved back before the reader changed display: nothing to wait for.
        if !pageEverResized, isFolded == wasFolded { return startedAt }
        let latest = startedAt.advanced(by: timing.maxWait)
        guard pageResized else { return latest }
        return min(lastInputAt.advanced(by: timing.quiet), latest)
    }
}

extension ReaderPosture {
    /// Folded onto the outer display. A change between folded and not folded
    /// moves the reader to the other display.
    nonisolated var isFolded: Bool { self == .closed }
}
