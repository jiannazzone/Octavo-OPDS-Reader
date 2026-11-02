import Foundation
import Observation

/// One try at a server at a time: setup's Sign in or Connect, Sign in again.
/// It gives up after `timeLimit`, and a new try, or `cancel()`, replaces it,
/// so the form never waits on a server that doesn't answer (a name lookup
/// has no time limit of its own; a port nothing answers on waits a minute).
/// A replaced try may still finish later (a name lookup can't be stopped);
/// `work` checks `isCurrent()` before it changes anything, so its result
/// goes nowhere.
@Observable
final class Attempt {
    private(set) var running = false

    @ObservationIgnored let timeLimit: Duration
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(timeLimit: Duration = .seconds(15)) {
        self.timeLimit = timeLimit
    }

    /// Starts `work`, replacing any try still running. `timedOut` runs if it
    /// hasn't finished within the time limit.
    func start(_ work: @escaping (_ isCurrent: @escaping () -> Bool) async -> Void, timedOut: @escaping () -> Void) {
        cancel()
        let current = generation
        let isCurrent = { [weak self] in self?.generation == current }
        running = true
        task = Task { [weak self] in
            await work(isCurrent)
            guard isCurrent() else { return }
            self?.ended()
        }
        let limit = timeLimit
        timer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled, isCurrent() else { return }
            self?.cancel()
            timedOut()
        }
    }

    /// Stops waiting for the try that's running, if any.
    func cancel() {
        generation += 1
        task?.cancel()
        timer?.cancel()
        task = nil
        timer = nil
        running = false
    }

    /// Until the running try ends (or gives up). For tests.
    func wait() async {
        await task?.value
        await timer?.value
    }

    private func ended() {
        timer?.cancel()
        timer = nil
        task = nil
        running = false
    }
}
