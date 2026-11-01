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
/// page has resized and the inputs have gone quiet, or until `maxWait`.
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
        /// (a hinge that flaps back, a device whose display doesn't change).
        /// The simulator's page resizes 0.2–2 s after the hinge, depending on
        /// load.
        var maxWait: Duration = .milliseconds(2000)
    }

    private(set) var startedAt: Instant
    private(set) var lastInputAt: Instant
    /// The page has reported a new size since the batch (re)started.
    private(set) var pageResized = false

    init(startedAt: Instant) {
        self.startedAt = startedAt
        lastInputAt = startedAt
    }

    /// The hinge moved across again before the batch ended: wait for this
    /// move's resize too.
    mutating func restart(at now: Instant) {
        startedAt = now
        lastInputAt = now
        pageResized = false
    }

    /// The hinge, the reader's size or the fold region changed.
    mutating func input(at now: Instant) {
        lastInputAt = max(lastInputAt, now)
    }

    /// The page reported its new size.
    mutating func pageResized(at now: Instant) {
        pageResized = true
        input(at: now)
    }

    /// When to lay out, if nothing else arrives.
    func deadline(_ timing: Timing) -> Instant {
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
