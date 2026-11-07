import ImageIO
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
        // Below the scrolling for a grid's covers, which may be gone before
        // they're ready. A full cover is the screen's point.
        .task(id: [book.source.rawValue, book.book.id.rawValue, book.book.cover?.cacheKey], priority: size == .full ? .userInitiated : .utility) {
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
    static let blurShare: CGFloat = 0.06
    /// How much the blurred copy is darkened, so the cover stands out from it.
    static let dimming = 0.18

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

extension View {
    /// A cover as the page it's on (Home's left page unfolded): blurred and
    /// darkened as `FittedCover` does its strips. `width` is the page's.
    func pageBlur(width: CGFloat) -> some View {
        blur(radius: width * FittedCover.blurShare, opaque: true)
            .overlay(.black.opacity(FittedCover.dimming))
            .clipped()
    }
}

/// Decoded covers in memory, keyed by library, image version and size, and
/// one fetch per cover at a time. What's fetched is also kept on the iPhone
/// (`CoverFiles`).
final class CoverCache {
    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]
    /// Covers the library said it hasn't got (or sent unreadable), so a
    /// cell scrolling back into view doesn't ask again. Not a failed
    /// connection: that cover loads once the server is back.
    private var missing: Set<String> = []
    private let files: CoverFiles
    /// How many times each server has been removed, so a fetch started before
    /// doesn't leave a cover once its server's are gone.
    private var removals: [LibrarySourceID: Int] = [:]

    init(files: CoverFiles = CoverFiles()) {
        self.files = files
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
        // An imported book's cover is on the iPhone already.
        let keepsFile = source != .files
        let removalsAtStart = removals[source, default: 0]
        let task = Task<UIImage?, Never> { [weak self, files] in
            if keepsFile, let data = await files.read(key, in: source), let image = await Self.decoded(data, size: size) {
                if cover.version == nil, await !files.isRecent(key, in: source) {
                    self?.refresh(cover, as: key, in: source, size: size, from: library, removalsAtStart: removalsAtStart)
                }
                return image
            }
            do {
                let data = try await library.cover(cover, size: size)
                guard let image = await Self.decoded(data, size: size) else {
                    self?.missing.insert(key)
                    return nil
                }
                if keepsFile { await self?.keep(data, as: key, in: source, removalsAtStart: removalsAtStart) }
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

    /// Remove server: its covers on the iPhone go.
    func removeFiles(of source: LibrarySourceID) async {
        removals[source, default: 0] += 1
        await files.removeAll(in: source)
    }

    /// Clear covers: on the iPhone and in memory, so each is fetched again when
    /// it's next shown.
    func clear() async {
        images.removeAllObjects()
        missing.removeAll()
        await files.removeAll()
    }

    func filesSize() async -> Int {
        await files.totalSize()
    }

    /// Fetches a kept cover again in the background: the one on the iPhone is
    /// already showing, and the new one shows when the cover is next drawn.
    private func refresh(
        _ cover: LibraryCover, as key: String, in source: LibrarySourceID, size: LibraryCoverSize,
        from library: any LibrarySource, removalsAtStart: Int
    ) {
        Task(priority: .utility) { [weak self] in
            guard let data = try? await library.cover(cover, size: size), let image = await Self.decoded(data, size: size) else { return }
            await self?.keep(data, as: key, in: source, removalsAtStart: removalsAtStart)
            self?.images.setObject(image, forKey: key as NSString)
        }
    }

    /// The check after the write catches a server removed during it.
    private func keep(_ data: Data, as key: String, in source: LibrarySourceID, removalsAtStart: Int) async {
        guard removals[source, default: 0] == removalsAtStart else { return }
        await files.write(data, as: key, in: source)
        if removals[source, default: 0] != removalsAtStart { await files.removeAll(in: source) }
    }

    /// A cover ready to draw, made off the main thread and no larger than it's
    /// ever shown: left to `UIImage(data:)`, it would be decoded as it first
    /// draws, mid-scroll. Not `byPreparingForDisplay()`: on the iOS 27.1
    /// simulator its images blank the whole window.
    @concurrent nonisolated static func decoded(_ data: Data, size: LibraryCoverSize) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size == .full ? 2400 : 600,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
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
