import Testing
import UIKit
@testable import Octavo

/// A view's cover load (`loadingCover`): an answer for a book the view has
/// moved on from doesn't land.
@MainActor
struct LoadedCoverTests {
    // The earlier current book's cover finished loading after Home had moved
    // on to the next one, and showed under its strip on every launch.
    @Test func anAnswerAfterCancellingShowsNothing() async {
        var shown: [LoadedCover] = []
        let answer = LateAnswer()
        let load = Task {
            await LoadedCover.load({ await answer.wait() }) { shown.append($0) }
        }
        // Moved on before the cover came. The cache's fetch doesn't stop for
        // that, so the cover still arrives.
        await answer.asked()
        load.cancel()
        answer.give(UIImage())
        await load.value
        #expect(shown.isEmpty)
    }

    @Test func aLoadShowsItsCoverOrThatThereIsNone() async {
        var shown: [LoadedCover] = []
        let image = UIImage()
        await LoadedCover.load({ image }) { shown.append($0) }
        await LoadedCover.load({ nil }) { shown.append($0) }
        #expect(shown == [LoadedCover(image: image, finished: true), LoadedCover(image: nil, finished: true)])
    }
}

/// A cover that comes when the test says, whether or not the task waiting for
/// it was cancelled, as `CoverCache`'s shared fetch does.
@MainActor
private final class LateAnswer {
    private var answer: CheckedContinuation<UIImage?, Never>?
    private var askers: [CheckedContinuation<Void, Never>] = []

    func wait() async -> UIImage? {
        await withCheckedContinuation { continuation in
            answer = continuation
            askers.forEach { $0.resume() }
            askers = []
        }
    }

    /// Returns once `wait` has been called.
    func asked() async {
        guard answer == nil else { return }
        await withCheckedContinuation { askers.append($0) }
    }

    func give(_ image: UIImage?) {
        answer?.resume(returning: image)
        answer = nil
    }
}
