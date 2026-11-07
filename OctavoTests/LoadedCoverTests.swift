import Testing
import UIKit
@testable import Octavo

/// A view's cover load (`loadingCover`): an answer for a book the view has
/// moved on from doesn't land.
@MainActor
struct LoadedCoverTests {
    // The earlier current book's cover finished loading after Home had moved
    // on to the next one, and showed under its strip on every launch.
    @Test func aLoadCancelledMeanwhileShowsNothing() async {
        var shown: [LoadedCover] = []
        let (answers, answer) = AsyncStream.makeStream(of: UIImage?.self)
        let load = Task {
            await LoadedCover.load({
                for await image in answers { return image }
                return nil
            }) { shown.append($0) }
        }
        // Moved on before the cover came.
        load.cancel()
        answer.yield(UIImage())
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
