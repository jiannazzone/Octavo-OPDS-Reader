import SwiftUI
import UIKit

/// The page as it was when the hinge moved, shown over the reader while a
/// fold settles and faded out once the new layout is in (decision 11).
struct ReaderFoldCover: Equatable {
    /// Seconds.
    static let fadeDuration = 0.3

    let id: Int
    let image: UIImage
    /// The page's size when the snapshot was taken, in points.
    let size: CGSize
    /// The page's background, to fill the rest of a bigger page.
    let background: Color
    var isFading = false

    init(id: Int, image: UIImage, size: CGSize) {
        self.id = id
        self.image = image
        self.size = size
        background = image.cornerColor ?? .white
    }
}

/// Draws a `ReaderFoldCover` at the page's top-left corner, the old page at
/// its own size. Ignores touches.
struct ReaderFoldCoverView: View {
    let cover: ReaderFoldCover
    /// The page's current size, which can be bigger than the snapshot.
    let pageSize: CGSize?

    var body: some View {
        ZStack(alignment: .topLeading) {
            cover.background
                .frame(width: max(pageSize?.width ?? 0, cover.size.width),
                       height: max(pageSize?.height ?? 0, cover.size.height))
            Image(uiImage: cover.image)
                .resizable()
                .frame(width: cover.size.width, height: cover.size.height)
        }
        .opacity(cover.isFading ? 0 : 1)
        .animation(.easeOut(duration: ReaderFoldCover.fadeDuration), value: cover.isFading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension UIImage {
    /// The colour a few pixels in from the top-left corner: the page's
    /// background, outside the text.
    nonisolated var cornerColor: Color? {
        guard let cgImage, cgImage.width > 4, cgImage.height > 4 else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Core Graphics counts rows from the bottom.
            let row = 3, column = 3
            context.draw(cgImage, in: CGRect(x: -column, y: -(cgImage.height - 1 - row), width: cgImage.width, height: cgImage.height))
            return true
        }
        guard drawn else { return nil }
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
