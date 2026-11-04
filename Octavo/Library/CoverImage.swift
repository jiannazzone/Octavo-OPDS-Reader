import OctavoKit
import SwiftUI
import UIKit

/// A book's cover from its library, in the view's frame (`FittedCover`). A
/// stand-in with the title shows while it loads, and for books without one.
struct CoverImage: View {
    let book: SourcedBook
    var size: LibraryCoverSize = .thumbnail
    @Environment(LibraryModel.self) private var library
    @State private var loaded: UIImage?

    var body: some View {
        let image = loaded ?? library.covers.cachedImage(for: book, size: size)
            ?? (size == .full ? library.covers.cachedImage(for: book, size: .thumbnail) : nil)
        // The image is in an overlay, so this view keeps the size it's
        // given: a filled image is larger than that, which would push
        // anything aligned to this view (the cover strip) off the screen.
        Color.clear
            .overlay {
                if let image {
                    FittedCover(image: image)
                } else {
                    StandInCover(title: book.book.title, author: book.book.authors.first ?? "", seed: book.book.id.rawValue)
                }
            }
            .clipped()
        // The pane beside a list keeps this view as the book changes.
        .task(id: [book.source.rawValue, book.book.id.rawValue, book.book.cover?.cacheKey]) {
            loaded = nil
            loaded = await library.coverImage(for: book, size: size)
        }
        .accessibilityHidden(true)
    }
}

/// A cover in its frame (decision 32): the whole cover on a blurred copy of
/// itself. It takes the size it's given and a filled cover overflows it, so
/// whatever holds it clips.
struct FittedCover: View {
    let image: UIImage

    /// A strip thinner than this would look like a glitch, and the crop that
    /// replaces it doesn't show.
    static let minimumStrip: CGFloat = 3
    /// The blur's radius, as a share of the frame's shorter side.
    private static let blurShare: CGFloat = 0.06
    /// How much the blurred copy is darkened, so the cover stands out from it.
    private static let dimming = 0.18

    /// Whether `cover` fills `frame`, cropped, instead of fitting inside it.
    static func fills(cover: CGSize, frame: CGSize) -> Bool {
        guard cover.width > 0, cover.height > 0 else { return true }
        let scale = min(frame.width / cover.width, frame.height / cover.height)
        let strip = max(frame.width - cover.width * scale, frame.height - cover.height * scale) / 2
        return strip < minimumStrip
    }

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size
            let picture = Image(uiImage: image).resizable()
            let filled = picture.scaledToFill().frame(width: frame.width, height: frame.height)
            if Self.fills(cover: image.size, frame: frame) {
                filled
            } else {
                ZStack {
                    // Kept to the frame: a ZStack offers its children its own
                    // size, so an overflowing copy would make the fit overflow.
                    filled
                        .blur(radius: min(frame.width, frame.height) * Self.blurShare, opaque: true)
                        .clipped()
                    Color.black.opacity(Self.dimming)
                    picture.scaledToFit()
                }
            }
        }
    }
}

/// Decoded covers in memory, keyed by library, image version and size, and
/// one fetch per cover at a time.
final class CoverCache {
    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]
    /// Covers the library said it hasn't got (or sent unreadable), so a
    /// cell scrolling back into view doesn't ask again. Not a failed
    /// connection: that cover loads once the server is back.
    private var missing: Set<String> = []

    init() {
        images.countLimit = 400
    }

    func cachedImage(for book: SourcedBook, size: LibraryCoverSize) -> UIImage? {
        book.book.cover.flatMap { cachedImage(for: $0, in: book.source, size: size) }
    }

    /// Any image a library hands out as a cover: a book's, an author's photo.
    func cachedImage(for cover: LibraryCover, in source: LibrarySourceID, size: LibraryCoverSize) -> UIImage? {
        images.object(forKey: key(cover, source, size) as NSString)
    }

    /// `nil` if the book has no cover or it couldn't be fetched.
    func image(for book: SourcedBook, size: LibraryCoverSize, from library: any LibrarySource) async -> UIImage? {
        guard let cover = book.book.cover else { return nil }
        return await image(for: cover, in: book.source, size: size, from: library)
    }

    /// `nil` if it couldn't be fetched.
    func image(for cover: LibraryCover, in source: LibrarySourceID, size: LibraryCoverSize, from library: any LibrarySource) async -> UIImage? {
        let key = key(cover, source, size)
        guard !missing.contains(key) else { return nil }
        if let image = images.object(forKey: key as NSString) { return image }
        if let task = loading[key] { return await task.value }
        let task = Task<UIImage?, Never> { [weak self] in
            do {
                let data = try await library.cover(cover, size: size)
                // Not `byPreparingForDisplay()`: on the iOS 27.1 simulator
                // its images blank the whole window.
                guard let image = UIImage(data: data) else {
                    self?.missing.insert(key)
                    return nil
                }
                return image
            } catch {
                if !(error is URLError || error is CancellationError) { self?.missing.insert(key) }
                return nil
            }
        }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { images.setObject(image, forKey: key as NSString) }
        return image
    }

    private func key(_ cover: LibraryCover, _ source: LibrarySourceID, _ size: LibraryCoverSize) -> String {
        "\(source.rawValue) \(size == .full ? "full" : "thumb") \(cover.cacheKey)"
    }
}

/// A coloured block with the title, for books without cover artwork.
struct StandInCover: View {
    let title: String
    let author: String
    /// Picks the colour, so a book keeps its colour.
    let seed: String

    var body: some View {
        // Spread by the golden ratio, so neighbouring IDs ("2", "4") differ.
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let hue = (Double(sum) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1)
        LinearGradient(
            colors: [Color(hue: hue, saturation: 0.45, brightness: 0.55), Color(hue: hue, saturation: 0.6, brightness: 0.3)],
            startPoint: .top, endPoint: .bottom
        )
        .overlay {
            // Sized to the cover, from a row's thumbnail to the full screen.
            GeometryReader { proxy in
                VStack(spacing: 8) {
                    // No title (a collection row's preview): colour only.
                    if !title.isEmpty {
                        Text(title)
                            .font(.system(.largeTitle, design: .serif).bold())
                    }
                    Text(author)
                        .font(.system(.title3, design: .serif))
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.1)
                .padding(proxy.size.width * 0.1)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}
