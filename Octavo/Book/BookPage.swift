import Foundation
import Observation
import OctavoKit
import UIKit

/// One book's cover page: its details, its cover image and whether its
/// sheet is expanded. A fold lays the screen out again, so this
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
    /// Finished as last set on this screen, over what the server sent.
    private(set) var markedFinished: Bool?
    /// Setting finished didn't reach the server.
    private(set) var finishedFailed = false
    /// The read status as last set here, over what the server sent
    /// (BookOrbit's, #120).
    private(set) var markedStatus: LibraryReadStatus?
    /// Setting the status didn't reach the server.
    private(set) var statusFailed = false
    /// Your rating as last set here, over what the server sent (#120):
    /// `.some(nil)` once cleared here.
    private(set) var markedRating: Int??
    /// Setting the rating didn't reach the server.
    private(set) var ratingFailed = false
    /// "Rate it": the book was just marked Finished, Skimmed or Abandoned
    /// here and isn't rated (Adam, 2026-11-13).
    private(set) var asksRating = false
    /// Ratings sent from here, so only the latest puts things back.
    @ObservationIgnored private var ratingRequests = 0
    /// The rating the server last took from here, over what it sent.
    @ObservationIgnored private var savedRating: Int??
    /// Where this iPhone keeps the mark for a server that doesn't.
    @ObservationIgnored private var finishedOnIPhone: (books: FinishedBooks, id: SourcedBook.ID)?
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

    /// Keeps the finished mark in `books` when the server doesn't keep one.
    func keepFinished(in books: FinishedBooks, as id: SourcedBook.ID) {
        finishedOnIPhone = (books, id)
    }

    /// The book and its library, once the screen has said
    /// (`keepFinished(in:as:)`).
    var sourcedID: SourcedBook.ID? { finishedOnIPhone?.id }

    var isFinished: Bool {
        if let markedFinished { return markedFinished }
        if let server = current.isFinished { return server }
        guard let finishedOnIPhone else { return false }
        return finishedOnIPhone.books.contains(finishedOnIPhone.id)
    }

    var readStatus: LibraryReadStatus? { markedStatus ?? current.readStatus }

    /// Your rating, 1 to 5 whole stars (BookOrbit's). `nil`: not rated.
    var rating: Int? { markedRating ?? current.rating }

    /// Marks the book finished, or not: on the server if it keeps the mark
    /// (BookOrbit), else on this iPhone. Shows the change at once and puts
    /// it back if the server refuses.
    func setFinished(_ finished: Bool, from source: any LibrarySource) async {
        let before = (markedFinished, markedStatus, asksRating)
        markedFinished = finished
        // Not finished is BookOrbit's `reading` (`BookOrbitSource.setFinished`).
        if source.tracksReadStatus { markedStatus = finished ? .read : .reading }
        asksRating = finished && shouldAskRating(after: .read, from: source)
        clearProblems()
        do {
            if source.tracksFinished {
                try await source.setFinished(finished, for: current)
            } else if let finishedOnIPhone {
                try finishedOnIPhone.books.set(finished, for: finishedOnIPhone.id)
            }
        } catch {
            (markedFinished, markedStatus, asksRating) = before
            finishedFailed = !(error is CancellationError)
        }
    }

    /// Sets the book's read status on the server (BookOrbit's), as
    /// `setFinished` does.
    func setStatus(_ status: LibraryReadStatus, from source: any LibrarySource) async {
        let before = (markedFinished, markedStatus, asksRating)
        markedStatus = status
        markedFinished = status == .read
        asksRating = shouldAskRating(after: status, from: source)
        clearProblems()
        do {
            try await source.setReadStatus(status, for: current)
        } catch {
            (markedFinished, markedStatus, asksRating) = before
            statusFailed = !(error is CancellationError)
        }
    }

    /// The statuses that end a reading, after which "Rate it" asks.
    static func endsAReading(_ status: LibraryReadStatus) -> Bool {
        switch status {
        case .read, .skimmed, .abandoned: true
        case .unread, .wantToRead, .reading, .onHold, .rereading, .other: false
        }
    }

    /// Whether "Rate it" asks once the book is marked `status`: a reading
    /// ended, on a server that keeps ratings, and not rated. Before the
    /// details arrive the rating is the list's, which can be older than
    /// the server's, so it doesn't ask then.
    private func shouldAskRating(after status: LibraryReadStatus, from source: any LibrarySource) -> Bool {
        guard Self.endsAReading(status), source.tracksRating else { return false }
        return (markedRating != nil || details != nil) && rating == nil
    }

    /// Rates the book on the server (BookOrbit's), 1 to 5 whole stars, or
    /// clears it with `nil`, as `setStatus` does. Answers "Rate it". Only
    /// the latest of several quick choices puts things back if refused.
    func setRating(_ rating: Int?, from source: any LibrarySource) async {
        ratingRequests += 1
        let request = ratingRequests
        let asked = asksRating
        markedRating = .some(rating)
        asksRating = false
        clearProblems()
        do {
            try await source.setRating(rating, for: current)
            savedRating = .some(rating)
            // An earlier choice that lands after the latest was refused:
            // the server has this one now.
            if request != ratingRequests, ratingFailed { markedRating = savedRating }
        } catch {
            guard request == ratingRequests else { return }
            markedRating = savedRating
            asksRating = asked
            ratingFailed = !(error is CancellationError)
        }
    }

    /// A new change starts with no problem showing.
    private func clearProblems() {
        finishedFailed = false
        statusFailed = false
        ratingFailed = false
    }

    /// ✕ on "Rate it", or leaving the screen: asks again only when the book
    /// is marked again.
    func dismissRatingPrompt() {
        asksRating = false
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

    /// The strip's place line: "30%" or "Not started", from where the book
    /// opens (`BookPlaces.progress(of:)`).
    static func placeLine(progress: Double?) -> String {
        guard let progress, progress > 0 else { return "Not started" }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "On hold · 30%", or "On hold" before it's started: a status the place
    /// alone would misstate (#120, Adam 2026-11-12).
    static func placeLine(progress: Double?, readStatus: LibraryReadStatus?) -> String {
        guard let word = readStatus?.placeWord else { return placeLine(progress: progress) }
        guard let progress, progress > 0 else { return word }
        return "\(word) · \(placeLine(progress: progress))"
    }

    /// "14% · BookOrbit": Home's, with several servers (decision 36).
    static func placeLine(progress: Double?, server: String?) -> String {
        let place = placeLine(progress: progress)
        return server.map { "\(place) · \($0)" } ?? place
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
    private var pages: [SourcedBook.ID: BookPage] = [:]
    private var recent: [SourcedBook.ID] = []
    private let limit: Int

    init(limit: Int = 20) {
        self.limit = limit
    }

    func page(for book: SourcedBook) -> BookPage {
        if let page = pages[book.id] { return page }
        let page = BookPage(book: book.book)
        pages[book.id] = page
        recent.append(book.id)
        if recent.count > limit {
            pages[recent.removeFirst()] = nil
        }
        return page
    }

    func existingPage(for id: SourcedBook.ID) -> BookPage? {
        pages[id]
    }

    /// `library`'s went, or it signed in again.
    func removeAll(in library: LibrarySourceID) {
        pages = pages.filter { $0.key.source != library }
        recent.removeAll { $0.source == library }
    }

    /// A book that's gone (an imported book removed).
    func remove(_ id: SourcedBook.ID) {
        pages[id] = nil
        recent.removeAll { $0 == id }
    }
}
