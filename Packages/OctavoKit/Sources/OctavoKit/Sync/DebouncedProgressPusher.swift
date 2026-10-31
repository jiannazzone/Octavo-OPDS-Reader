import Foundation

/// Pushes the latest reading position once the reader has been still for
/// `delay`.
///
/// foliate-js reports three or four positions per page turn as the layout
/// settles, and a reader flicking through pages reports many more. Only the
/// last one in a burst is pushed. Pushes run one at a time and in order, so
/// an older position can never land after a newer one. A failed push keeps
/// its position for the next `submit` or `flush`, unless a newer one arrived.
public actor DebouncedProgressPusher<C: Clock> where C.Duration == Duration {
    public nonisolated let delay: Duration
    private let clock: C
    private let push: @Sendable (ReadingPosition) async throws -> Void

    /// The position waiting to be pushed.
    public private(set) var pending: ReadingPosition?
    /// The last position the backend accepted.
    public private(set) var lastPushed: ReadingPosition?
    public private(set) var lastError: (any Error)?

    private var timer: Task<Void, Never>?
    /// The last push scheduled. Each push waits for the one before it.
    private var chain: Task<Void, Never>?

    public init(delay: Duration, clock: C, push: @escaping @Sendable (ReadingPosition) async throws -> Void) {
        self.delay = delay
        self.clock = clock
        self.push = push
    }

    /// Replaces the pending position and restarts the quiet period.
    public func submit(_ position: ReadingPosition) {
        pending = position
        timer?.cancel()
        // The deadline is fixed now, not when the timer task first runs.
        let deadline = clock.now.advanced(by: delay)
        timer = Task { [clock] in
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return
            }
            self.timerFired()
        }
    }

    /// Pushes the pending position now, and returns once it (and any push
    /// before it) has finished. Call when the book closes.
    public func flush() async {
        timer?.cancel()
        timer = nil
        await schedulePush().value
    }

    /// Waits for the running timer and pushes to finish. Tests only: it
    /// never returns while a timer is still waiting for its deadline.
    func waitUntilIdle() async {
        await timer?.value
        await chain?.value
    }

    private func timerFired() {
        // A `submit` may have replaced this timer while it was waking up.
        guard !Task.isCancelled else { return }
        timer = nil
        _ = schedulePush()
    }

    /// Unstructured, so cancelling a timer never cancels a push in flight.
    private func schedulePush() -> Task<Void, Never> {
        let previous = chain
        let task = Task {
            await previous?.value
            await self.pushPending()
        }
        chain = task
        return task
    }

    private func pushPending() async {
        guard let position = pending else { return }
        pending = nil
        guard position != lastPushed else { return }
        do {
            try await push(position)
            lastPushed = position
            lastError = nil
        } catch {
            lastError = error
            if pending == nil { pending = position }
        }
    }
}

extension DebouncedProgressPusher where C == ContinuousClock {
    public init(delay: Duration, push: @escaping @Sendable (ReadingPosition) async throws -> Void) {
        self.init(delay: delay, clock: ContinuousClock(), push: push)
    }
}
