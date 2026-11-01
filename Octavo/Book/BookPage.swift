import Foundation
import Observation
import OctavoKit
import UIKit

/// One book's cover page: its details, its cover image and whether its
/// sheet is expanded. A fold rebuilds the screens (`PaneStack`), so this
/// lives in `BookPages` rather than in the view, and the sheet stays as it
/// was.
@Observable
final class BookPage {
    let book: LibraryBook
    private(set) var details: LibraryBookDetails?
    private(set) var detailsFailed = false
    private(set) var cover: UIImage?
    /// The cover has loaded, or there's none to load: show the title
    /// instead if `cover` is still `nil`.
    private(set) var coverFinished = false
    /// The server's name for the details' From row (decision 20).
    private(set) var serverName: String?
    var isExpanded = false
    var showsFullDescription = false
    /// The saved position lives on disk, which isn't observed; this
    /// changes when the reader closes, so the strip reads it again.
    private var positionsChanged = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(book: LibraryBook) {
        self.book = book
    }

    /// The details' book where they've loaded (it has the files and the
    /// cover), else the list's.
    var current: LibraryBook { details?.book ?? book }

    /// Loads the details, the server's name and the full-size cover, once.
    /// The page owns the work, so a fold that rebuilds the view doesn't
    /// cancel it.
    func load(from source: any LibrarySource) {
        guard loadTask == nil else { return }
        loadTask = Task {
            async let details = loadDetails(from: source)
            async let name = try? source.root().title
            if let cover = book.cover { await loadCover(cover, from: source) }
            serverName = await name
            let fetched = await details
            self.details = fetched
            if book.cover == nil, let cover = fetched?.book.cover { await loadCover(cover, from: source) }
            coverFinished = true
        }
    }

    /// The reader closed this book, having saved its position.
    func readerClosed() {
        positionsChanged += 1
    }

    func retryDetails(from source: any LibrarySource) async {
        guard detailsFailed else { return }
        detailsFailed = false
        details = await loadDetails(from: source)
    }

    private func loadDetails(from source: any LibrarySource) async -> LibraryBookDetails? {
        do {
            return try await source.details(for: book)
        } catch {
            detailsFailed = !(error is CancellationError)
            return nil
        }
    }

    private func loadCover(_ cover: LibraryCover, from source: any LibrarySource) async {
        guard let data = try? await source.cover(cover, size: .full) else { return }
        self.cover = await Self.decode(data)
    }

    /// Not `byPreparingForDisplay()`: on the iOS 27.1 simulator its images
    /// blank the whole window (`docs/notes/home-library.md`).
    nonisolated private static func decode(_ data: Data) async -> UIImage? {
        UIImage(data: data)
    }

    // MARK: What the sheet shows

    /// Progress through the book, 0...1: the iPhone's saved position if
    /// there is one, else the server's (decision on #14; #11 reconciles the
    /// two). `nil` if neither knows.
    func progress(positions: ReadingPositionStore = ReadingPositionStore()) -> Double? {
        _ = positionsChanged
        if let file = current.readableFile, let position = positions.position(forBook: file.storageKey) {
            return position.fraction
        }
        return current.progress
    }

    /// The strip's place line: "30%" or "Not started". #11 adds the
    /// chapter.
    static func placeLine(progress: Double?) -> String {
        guard let progress, progress > 0 else { return "Not started" }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    /// The description as plain text: it may carry the book's own markup.
    var plainDescription: String? {
        guard let html = details?.description else { return nil }
        let text = PlainText.fromHTML(html)
        return text.isEmpty ? nil : text
    }

    var authorLine: String {
        let names = details.map { $0.authors.map(\.title) } ?? book.authors
        return (names.isEmpty ? book.authors : names).formatted(.list(type: .and))
    }

    /// "Sherlock Holmes · 3", or the series' name alone if unnumbered.
    var seriesLine: String? {
        let series = details?.series.first ?? current.series
        guard let series else { return nil }
        guard let position = series.position else { return series.name }
        return "\(series.name) · \(position.formatted(.number.precision(.fractionLength(0...1))))"
    }

    var collectionsLine: String? {
        guard let collections = details?.collections, !collections.isEmpty else { return nil }
        return collections.map(\.title).joined(separator: " · ")
    }

    /// "EPUB · 1.2 MB": the file the reader would open, else the primary.
    var fileLine: String? {
        guard let file = current.readableFile ?? current.primaryFile else { return nil }
        let parts = [
            file.format?.uppercased(),
            file.sizeBytes.map { Int64($0).formatted(.byteCount(style: .file)) },
        ]
        let line = parts.compactMap(\.self).joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    var addedLine: String? {
        details?.addedAt?.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

/// The cover pages seen recently, so a fold or going back and forth keeps
/// their state and doesn't load them again. Not observed: views get a
/// page from here while drawing, and each page is observed on its own.
final class BookPages {
    private var pages: [LibraryBookID: BookPage] = [:]
    private var recent: [LibraryBookID] = []
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = limit
    }

    func page(for book: LibraryBook) -> BookPage {
        if let page = pages[book.id] { return page }
        let page = BookPage(book: book)
        pages[book.id] = page
        recent.append(book.id)
        if recent.count > limit {
            pages[recent.removeFirst()] = nil
        }
        return page
    }

    func existingPage(for id: LibraryBookID) -> BookPage? {
        pages[id]
    }

    /// The source changed (another server, or signed in again).
    func removeAll() {
        pages = [:]
        recent = []
    }
}
