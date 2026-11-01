import OctavoKit
import SwiftUI
import UIKit

/// A book's cover from its library, filling the view. A stand-in with the
/// title shows while it loads, and for books without one.
struct CoverImage: View {
    let book: SourcedBook
    var size: LibraryCoverSize = .thumbnail
    @Environment(LibraryModel.self) private var library
    @State private var loaded: UIImage?

    var body: some View {
        let image = loaded ?? library.covers.cachedImage(for: book, size: size)
            ?? (size == .full ? library.covers.cachedImage(for: book, size: .thumbnail) : nil)
        // The image fills an overlay, so this view keeps the size it's
        // given: a filled image is larger than that, which would push
        // anything aligned to this view (the cover strip) off the screen.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
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

/// Decoded covers in memory, keyed by library, image version and size, and
/// one fetch per cover at a time.
final class CoverCache {
    private let images = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]

    init() {
        images.countLimit = 400
    }

    func cachedImage(for book: SourcedBook, size: LibraryCoverSize) -> UIImage? {
        key(book, size).flatMap { images.object(forKey: $0 as NSString) }
    }

    /// `nil` if the book has no cover or it couldn't be fetched.
    func image(for book: SourcedBook, size: LibraryCoverSize, from library: any LibrarySource) async -> UIImage? {
        guard let key = key(book, size), let cover = book.book.cover else { return nil }
        if let image = images.object(forKey: key as NSString) { return image }
        if let task = loading[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            guard let data = try? await library.cover(cover, size: size) else { return nil }
            // Not `byPreparingForDisplay()`: on the iOS 27.1 simulator its
            // images blank the whole window.
            return UIImage(data: data)
        }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image { images.setObject(image, forKey: key as NSString) }
        return image
    }

    private func key(_ book: SourcedBook, _ size: LibraryCoverSize) -> String? {
        book.book.cover.map { "\(book.source.rawValue) \(size == .full ? "full" : "thumb") \($0.cacheKey)" }
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
