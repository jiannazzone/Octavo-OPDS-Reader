import Foundation
@testable import OctavoKit
import Synchronization
import Testing

/// Records pushes; fails the first `failures` of them.
private final class Backend: Sendable {
    private let state: Mutex<(pushes: [ReadingPosition], failures: Int)>

    init(failures: Int = 0) {
        state = Mutex(([], failures))
    }

    var pushes: [ReadingPosition] { state.withLock { $0.pushes } }

    func push(_ position: ReadingPosition) throws {
        try state.withLock { state in
            state.pushes.append(position)
            if state.failures > 0 {
                state.failures -= 1
                throw URLError(.notConnectedToInternet)
            }
        }
    }
}

private func position(_ n: Int) -> ReadingPosition {
    ReadingPosition(cfi: "epubcfi(/6/4!/4/2/\(n * 2)/1:0)", fraction: Double(n) / 100)
}

struct DebouncedProgressPusherTests {
    let clock = ManualClock()
    let delay = Duration.seconds(2)

    private func makePusher(_ backend: Backend) -> DebouncedProgressPusher<ManualClock> {
        DebouncedProgressPusher(delay: delay, clock: clock) { try backend.push($0) }
    }

    @Test func pushesOnlyTheLastPositionOfABurst() async {
        let backend = Backend()
        let pusher = makePusher(backend)

        // One page turn: foliate reports the same page several times.
        for n in 1...4 { await pusher.submit(position(n)) }
        clock.advance(by: delay)
        await pusher.waitUntilIdle()

        #expect(backend.pushes == [position(4)])
        #expect(await pusher.lastPushed == position(4))
        #expect(await pusher.pending == nil)
    }

    @Test func waitsForTheReaderToBeStill() async {
        let backend = Backend()
        let pusher = makePusher(backend)

        await pusher.submit(position(1))
        clock.advance(by: .seconds(1.5))
        await pusher.submit(position(2))
        // 2 s after the first position, but only 0.5 s after the second.
        clock.advance(by: .seconds(0.5))
        for _ in 0..<10 { await Task.yield() }
        #expect(backend.pushes.isEmpty)
        #expect(await pusher.pending == position(2))

        clock.advance(by: .seconds(1.5))
        await pusher.waitUntilIdle()
        #expect(backend.pushes == [position(2)])
    }

    @Test func flushPushesImmediatelyAndCancelsTheTimer() async {
        let backend = Backend()
        let pusher = makePusher(backend)

        await pusher.submit(position(1))
        await pusher.flush()
        #expect(backend.pushes == [position(1)])

        clock.advance(by: delay)
        for _ in 0..<10 { await Task.yield() }
        #expect(backend.pushes == [position(1)])
    }

    @Test func flushWithNothingPendingDoesNothing() async {
        let backend = Backend()
        await makePusher(backend).flush()
        #expect(backend.pushes.isEmpty)
    }

    @Test func skipsAPositionTheBackendAlreadyHas() async {
        let backend = Backend()
        let pusher = makePusher(backend)

        await pusher.submit(position(1))
        await pusher.flush()
        await pusher.submit(position(1))
        await pusher.flush()

        #expect(backend.pushes == [position(1)])
    }

    @Test func keepsAFailedPositionForTheNextFlush() async {
        let backend = Backend(failures: 1)
        let pusher = makePusher(backend)

        await pusher.submit(position(1))
        clock.advance(by: delay)
        await pusher.waitUntilIdle()
        #expect(await pusher.lastError != nil)
        #expect(await pusher.pending == position(1))
        #expect(await pusher.lastPushed == nil)

        await pusher.flush()
        #expect(backend.pushes == [position(1), position(1)])
        #expect(await pusher.lastError == nil)
        #expect(await pusher.lastPushed == position(1))
    }

    @Test func aNewerPositionReplacesAFailedOne() async {
        let backend = Backend(failures: 1)
        let pusher = makePusher(backend)

        await pusher.submit(position(1))
        await pusher.flush()
        await pusher.submit(position(2))
        await pusher.flush()

        #expect(backend.pushes == [position(1), position(2)])
        #expect(await pusher.lastPushed == position(2))
    }
}
