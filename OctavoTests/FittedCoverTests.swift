import SwiftUI
import Testing
import UIKit
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

    /// The view, not just the rule. A solid red cover: its strips show the
    /// darkened blur, so the top of the frame is darker than the middle.
    @MainActor @Test func aSquareCoverSitsInsideItsFrame() throws {
        let cover = try draw(solidRed: CGSize(width: 100, height: 100))
        #expect(try red(cover, x: 50, y: 5) < red(cover, x: 50, y: 75))
    }

    @MainActor @Test func aNarrowCoverSitsInsideItsFrame() throws {
        let cover = try draw(solidRed: CGSize(width: 50, height: 150))
        #expect(try red(cover, x: 5, y: 75) < red(cover, x: 50, y: 75))
    }

    @MainActor @Test func aCoverThatFillsHasNoStrips() throws {
        let cover = try draw(solidRed: CGSize(width: 100, height: 150))
        #expect(try red(cover, x: 50, y: 5) == red(cover, x: 50, y: 75))
    }

    /// `coverSize` drawn by `FittedCover` in a 100×150 frame.
    @MainActor private func draw(solidRed coverSize: CGSize) throws -> CGImage {
        let cover = UIGraphicsImageRenderer(size: coverSize).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: coverSize))
        }
        let renderer = ImageRenderer(content: FittedCover(image: cover).frame(width: 100, height: 150).clipped())
        return try #require(renderer.cgImage)
    }

    private func red(_ image: CGImage, x: Int, y: Int) throws -> UInt8 {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
        return pixel[0]
    }
}
