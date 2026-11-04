import CoreGraphics
import Testing
@testable import Octavo

/// When a cover fills its frame instead of fitting on its blur (decision 32).
struct FittedCoverTests {
    let foldedScreen = CGSize(width: 466, height: 678)
    let leftPage = CGSize(width: 455.5, height: 669)
    let gridCell = CGSize(width: 106, height: 159)

    @Test func ordinaryCoversFitOnTheLargePage() {
        // Moby-Dick, Trust, Alice: strips of 17, 16 and 17 pt folded.
        #expect(!FittedCover.fills(cover: CGSize(width: 780, height: 1227), frame: foldedScreen))
        #expect(!FittedCover.fills(cover: CGSize(width: 1409, height: 2200), frame: foldedScreen))
        #expect(!FittedCover.fills(cover: CGSize(width: 800, height: 1104), frame: foldedScreen))
        #expect(!FittedCover.fills(cover: CGSize(width: 1409, height: 2200), frame: leftPage))
    }

    @Test func aStripThinnerThanTheMinimumFills() {
        // Trust is 2 pt each side in a grid cell; Alice is 6 pt top and bottom.
        #expect(FittedCover.fills(cover: CGSize(width: 1409, height: 2200), frame: gridCell))
        #expect(!FittedCover.fills(cover: CGSize(width: 800, height: 1104), frame: gridCell))
    }

    @Test func coverWithTheFramesShapeFills() {
        #expect(FittedCover.fills(cover: CGSize(width: 1400, height: 2100), frame: gridCell))
        #expect(FittedCover.fills(cover: foldedScreen, frame: foldedScreen))
    }

    @Test func aSquareCoverAlwaysFits() {
        let square = CGSize(width: 1000, height: 1000)
        #expect(!FittedCover.fills(cover: square, frame: foldedScreen))
        #expect(!FittedCover.fills(cover: square, frame: gridCell))
        #expect(!FittedCover.fills(cover: square, frame: CGSize(width: 22, height: 33)))
    }

    @Test func anImageWithoutASizeFills() {
        #expect(FittedCover.fills(cover: .zero, frame: foldedScreen))
    }
}
