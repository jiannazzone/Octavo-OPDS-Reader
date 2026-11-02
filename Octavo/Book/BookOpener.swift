import Foundation
import Observation
import OctavoKit

/// A book ready to read: its library entry and the file on the iPhone.
nonisolated struct OpenedBook: Hashable, Sendable {
    var book: LibraryBook
    var file: LibraryFile
    var reader: ReaderBook

    init(book: LibraryBook, file: LibraryFile, url: URL) {
        self.book = book
        self.file = file
        reader = ReaderBook(fileURL: url, id: file.storageKey)
    }
}

/// Downloads books and opens them: Download on a book's screen, Open, an
/// unfold on a downloaded book's screen and Home's rows all come here. A
/// download's progress shows on the book's screen and its covers, and the
/// book stays on the iPhone until Remove download.
///
/// It lives in `ShellModel`, so a download keeps going, and its progress
/// keeps showing, while a fold rebuilds the screens.
@Observable
final class BookOpener {
    enum Status: Equatable {
        case notDownloaded
        /// `opensWhenDone`: Open or an unfold asked for it ("Opens when
        /// it's done"). A plain Download from the details doesn't open.
        case downloading(fraction: Double, opensWhenDone: Bool)
        /// `offline`: the iPhone has no connection ("Needs a connection to
        /// download."). Try again keeps what was asked for.
        case failed(offline: Bool, opensWhenDone: Bool)
        case downloaded
    }

    /// Called once a book asked to open is on the iPhone.
    var onOpen: (OpenedBook) -> Void = { _ in }

    private let files: any BookFiles
    private var statuses: [LibraryBookID: Status] = [:]
    private var tasks: [LibraryBookID: Task<Void, Never>] = [:]
    /// Files on disk aren't observed; this changes when one is removed, so
    /// covers and screens look again.
    private var removals = 0

    init(files: any BookFiles = StoredBookFiles.moved()) {
        self.files = files
    }

    func status(of book: LibraryBook) -> Status {
        _ = removals
        if let status = statuses[book.id] { return status }
        guard let file = book.readableFile, files.localFile(for: file) != nil else { return .notDownloaded }
        return .downloaded
    }

    /// Whether the reader can open `book`: it has a file in a format the
    /// reader reads. A book that lists no files yet (an OPDS entry before
    /// its details load) gets the benefit of the doubt.
    func canOpen(_ book: LibraryBook) -> Bool {
        book.files.isEmpty || book.readableFile != nil
    }

    /// Opens `book` now if it's on the iPhone, else downloads it and opens
    /// it when it's done.
    func open(_ book: LibraryBook, from source: any LibrarySource) {
        guard canOpen(book) else { return }
        switch statuses[book.id] {
        case .downloading(let fraction, _):
            statuses[book.id] = .downloading(fraction: fraction, opensWhenDone: true)
            return
        default:
            break
        }
        if let file = book.readableFile, let url = files.localFile(for: file) {
            statuses[book.id] = nil
            onOpen(OpenedBook(book: book, file: file, url: url))
        } else {
            start(book, from: source, opensWhenDone: true)
        }
    }

    /// Downloads `book` without opening it (the details' Download button).
    func download(_ book: LibraryBook, from source: any LibrarySource) {
        guard canOpen(book), tasks[book.id] == nil, status(of: book) != .downloaded else { return }
        start(book, from: source, opensWhenDone: false)
    }

    /// Try again on the strip: the same request again.
    func retry(_ book: LibraryBook, from source: any LibrarySource) {
        guard case .failed(_, let opensWhenDone) = statuses[book.id] else { return }
        statuses[book.id] = nil
        if opensWhenDone { open(book, from: source) } else { download(book, from: source) }
    }

    /// Cancel on the strip. Leaves no partial file.
    func cancel(_ book: LibraryBook) {
        tasks[book.id]?.cancel()
        tasks[book.id] = nil
        statuses[book.id] = nil
    }

    /// Remove download: deletes the book's file from the iPhone. Its saved
    /// place stays, so it opens where it was if it's downloaded again.
    func removeDownload(_ book: LibraryBook) {
        cancel(book)
        guard let file = book.readableFile else { return }
        try? files.remove(file)
        removals += 1
    }

    /// Forgets a failure, so the strip shows Open again.
    func clearFailure(_ book: LibraryBook) {
        if case .failed = statuses[book.id] { statuses[book.id] = nil }
    }

    private func start(_ book: LibraryBook, from source: any LibrarySource, opensWhenDone: Bool) {
        tasks[book.id]?.cancel()
        statuses[book.id] = .downloading(fraction: 0, opensWhenDone: opensWhenDone)
        let files = files
        tasks[book.id] = Task {
            do {
                // A list entry may not list its files; the details do.
                var full = book
                if full.files.isEmpty { full = try await source.details(for: book).book }
                guard let file = full.readableFile else { throw BookFilesError.unreadableFormat }
                let id = book.id
                let url = try await files.download(file, from: source) { fraction in
                    Task { @MainActor [weak self] in self?.progressed(id, to: fraction) }
                }
                try Task.checkCancellation()
                finished(full, file: file, url: url)
            } catch {
                failed(book, error)
            }
        }
    }

    private func progressed(_ id: LibraryBookID, to fraction: Double) {
        guard case .downloading(let shown, let opens) = statuses[id] else { return }
        // Whole percents: the strip shows no more, and each change redraws it.
        let rounded = (fraction * 100).rounded(.down) / 100
        if rounded > shown { statuses[id] = .downloading(fraction: rounded, opensWhenDone: opens) }
    }

    private func finished(_ book: LibraryBook, file: LibraryFile, url: URL) {
        guard case .downloading(_, let opens) = statuses[book.id] else { return }
        tasks[book.id] = nil
        statuses[book.id] = nil
        if opens { onOpen(OpenedBook(book: book, file: file, url: url)) }
    }

    private func failed(_ book: LibraryBook, _ error: any Error) {
        // Cancelled: `cancel` has already reset the status.
        guard case .downloading(_, let opens) = statuses[book.id], !Self.isCancellation(error) else { return }
        tasks[book.id] = nil
        statuses[book.id] = .failed(offline: Self.isOffline(error), opensWhenDone: opens)
    }

    static func isOffline(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
