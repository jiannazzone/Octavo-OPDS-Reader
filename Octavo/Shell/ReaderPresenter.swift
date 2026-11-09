import Foundation
import Observation
import OctavoKit
import SwiftUI
import UIKit

/// The reader over the tabs: the book open in it, every way in and out, and
/// the cover's motion between it and the screen it opens from (decision 28).
/// The shell owns it and says what's under the reader (`underneath`); it
/// moves no screens itself (`docs/notes/ui-audit.md`, item 4).
@Observable
final class ReaderPresenter {
    /// What's under the reader as a book opens or closes, from the shell.
    struct Underneath {
        /// Home's own page is the top of the tab showing.
        var onHome = false
        /// The screen on top of the tab showing.
        var top: ShellRoute?
        /// The tour is playing: only its sample book opens.
        var inTour = false
    }

    /// How a book comes to open, which decides its motion.
    enum Opening {
        /// Open, or a row: from the book's own screen, or Home's left page
        /// unfolded, its cover opens it; from anywhere else the reader fades
        /// in.
        case tapped
        /// The Duo unfolded on the book's screen: the fold is the cover's
        /// motion, and the leaves alone play (decision 10).
        case unfolded
        /// A motion already made (the tour's cover).
        case motion(ReaderCoverMotion)
    }

    /// The book open in the reader, which covers the tabs.
    var reading: OpenedBook? {
        didSet {
            if let closed = oldValue, closed != reading {
                places.readerClosed()
                library.mergeContinueReading()
            }
        }
    }
    /// The library of the book in the reader, for its screen when a fold
    /// closes it.
    private var readingSource: LibrarySourceID?
    /// The books asked to open, until they do.
    private var requested: Set<SourcedBook.ID> = []
    /// How the next book to reach the reader opens. Set only once a book is
    /// on its way, so an unfold that opens nothing leaves the next Open
    /// alone.
    @ObservationIgnored private var nextOpening = Opening.tapped

    /// The cover opening the book, drawn over the reader while it opens.
    /// One taken away before it's over stops for good.
    var coverMotion: ReaderCoverMotion? {
        didSet {
            if oldValue !== coverMotion { oldValue?.cancel() }
        }
    }
    /// Where Home and the books' screens show their covers, for the cover's
    /// motion.
    let coverSpots = CoverSpots()

    /// What's under the reader, asked as a book opens or closes.
    @ObservationIgnored var underneath: () -> Underneath = { Underneath() }

    private let library: LibraryModel
    private let opener: BookOpener
    private let places: BookPlaces
    /// Where the reading settings the motion goes by are kept.
    private let defaults: UserDefaults

    init(library: LibraryModel, opener: BookOpener, places: BookPlaces, defaults: UserDefaults) {
        self.library = library
        self.opener = opener
        self.places = places
        self.defaults = defaults
        opener.onOpen = { [weak self] in self?.opened($0) }
    }

    // MARK: In

    /// Opens `book` in the reader, downloading it first if it isn't on the
    /// iPhone yet, and once it opens puts it first in Continue reading.
    func open(_ book: SourcedBook, _ opening: Opening = .tapped) {
        guard let source = library.source(for: book.source), opener.canOpen(book.book) else { return }
        requested.insert(book.id)
        nextOpening = opening
        if opener.status(of: book) != .downloaded { library.bookDownloading(book) }
        opener.open(book, from: source)
    }

    /// A copy with no library behind it (the tour's replay), straight into
    /// the reader.
    func open(copy book: OpenedBook, _ opening: Opening = .tapped) {
        nextOpening = opening
        opened(book)
    }

    /// Nothing asked of `server` opens now that it's gone (Remove server).
    func forgetRequests(in server: LibrarySourceID) {
        requested = requested.filter { $0.source != server }
    }

    /// Only a book that reaches the reader joins Continue reading: not one
    /// whose download failed or was cancelled.
    private func opened(_ book: OpenedBook) {
        let source = requested.remove(SourcedBook.ID(source: book.source, book: book.book.id)).map(\.source)
        // A download that finishes during the tour stays on the iPhone. It
        // mustn't open with the tour's card, or a replay's place.
        if underneath().inTour, book.book.id != .sample { return }
        if source != nil {
            library.bookOpened(SourcedBook(source: book.source, book: book.book))
        }
        let motion: ReaderCoverMotion? = switch nextOpening {
        case .tapped: coverMotion(opening: book)
        case .unfolded: leavesMotion(opening: book)
        case .motion(let made): made
        }
        nextOpening = .tapped
        motion?.onFinished = { [weak self, weak motion] in
            if self?.coverMotion === motion { self?.coverMotion = nil }
        }
        coverMotion = motion
        readingSource = source
        reading = book
    }

    // MARK: Out

    /// Every way out of the reader: Back, a fold, an import, the tour, and
    /// `change` with it. It goes at once, with no animation: anything still
    /// animating in a leaving reader (the tour card's fade, the ring's pulse)
    /// keeps it and its web page on screen a moment longer, and a fold
    /// meanwhile has SwiftUI rebuild that web view, which WebKit traps on
    /// (`AppShell`). A cover still opening the book goes with it; Back's
    /// cover, closing it (`closing`), plays on.
    func close(_ change: () -> Void = {}) {
        if coverMotion?.closing == false { coverMotion = nil }
        nextOpening = .tapped
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            reading = nil
            change()
        }
    }

    /// Back from the reader (not a fold, whose motion is the fold): onto the
    /// book's own screen, or Home with the book's cover on its left page,
    /// the opening plays backwards. `pages` are the reader's, taken as Back
    /// was tapped; the reader then goes at once.
    func closing(_ pages: ReaderCoverPages) {
        guard let book = reading else { return }
        coverMotion = nil
        let motion = coverMotion(for: book, closing: pages)
        motion?.onFinished = { [weak self, weak motion] in
            if self?.coverMotion === motion { self?.coverMotion = nil }
        }
        coverMotion = motion
    }

    /// The open book as its library lists it, for its screen: `nil` for a
    /// copy with none (the tour's replay).
    var readingBook: SourcedBook? {
        guard let reading, let readingSource else { return nil }
        return SourcedBook(source: readingSource, book: reading.book)
    }

    // MARK: The cover's motion (decision 28)

    /// From the book's own screen, or Home's left page unfolded, its cover
    /// opens it; from anywhere else the reader fades in as before.
    private func coverMotion(opening book: OpenedBook) -> ReaderCoverMotion? {
        guard reading == nil else { return nil }
        return coverMotion(for: book, closing: nil)
    }

    /// Unfolding on a cover, past page 1 the leaves alone. It goes by where the
    /// book's screen says it opens, so they're moving by the time your page is
    /// ready; the last one carries the page itself.
    private func leavesMotion(opening book: OpenedBook) -> ReaderCoverMotion? {
        guard reading == nil, let progress = places.progress(of: SourcedBook(source: book.source, book: book.book)),
              ReaderLeaves.play(fraction: progress, pageTurn: pageTurn, reduceMotion: UIAccessibility.isReduceMotionEnabled)
        else { return nil }
        let window = UIWindow.key
        return ReaderCoverMotion(
            unfoldingAt: progress, windowSize: window?.bounds.size ?? .zero, paper: window.map(Self.paper(in:)) ?? .white, leafStyle: leafStyle
        )
    }

    /// The sample book's cover at `frame` (in the window) opening it, as a
    /// book's screen does: the tour's Continue without closing. No left page
    /// to start from, and the reader fades in.
    func sampleCoverMotion(from frame: CGRect) -> ReaderCoverMotion? {
        guard let window = UIWindow.key, frame.width > 0, frame.height > 0,
              let screen = window.snapshotView(afterScreenUpdates: false)
        else { return nil }
        let book = SampleBook.book
        return ReaderCoverMotion(
            cover: SampleBook.bundledCover.flatMap { UIImage(contentsOfFile: $0.path) },
            title: book.title, author: book.authors.formatted(.list(type: .and)),
            coverFrame: frame, windowSize: window.bounds.size,
            bookScreen: ReaderSnapshot(view: screen, frame: window.bounds),
            spread: true, reduceMotion: UIAccessibility.isReduceMotionEnabled,
            paper: Self.paper(in: window), pageTurn: pageTurn, leafStyle: leafStyle
        )
    }

    private var pageTurn: ReaderPageTurn {
        defaults.string(forKey: ReaderPageTurn.key).flatMap(ReaderPageTurn.init(rawValue:)) ?? .standard
    }

    private var leafStyle: ReaderLeafStyle {
        ReaderLeafStyle(
            appearance: UserDefaults.standard.string(forKey: ReaderAppearance.key).flatMap(ReaderAppearance.init(rawValue:)) ?? ReaderAppearance(),
            margins: defaults.string(forKey: ReaderMargins.key).flatMap(ReaderMargins.init(rawValue:)) ?? .standard
        )
    }

    /// The cover's motion for `book` over its own screen, the top one, or
    /// Home unfolded: a picture of the screen to open from, or of your pages
    /// to close from.
    private func coverMotion(for book: OpenedBook, closing pages: ReaderCoverPages?) -> ReaderCoverMotion? {
        let id = SourcedBook.ID(source: book.source, book: book.book.id)
        let under = underneath()
        // The tour covers Home.
        guard let spot = coverSpots.spot(for: id, onHome: under.onHome && !under.inTour, top: under.top),
              let window = UIWindow.key, window.bounds.intersects(spot.frame)
        else { return nil }
        let screen = pages == nil ? window.snapshotView(afterScreenUpdates: false) : nil
        guard pages != nil || screen != nil else { return nil }
        return ReaderCoverMotion(
            cover: spot.image, title: spot.title, author: spot.author,
            coverFrame: spot.frame, windowSize: window.bounds.size, bookScreen: screen.map { ReaderSnapshot(view: $0, frame: window.bounds) },
            closing: pages,
            // Cover | Details, as its screen draws it; else the cover fills
            // its screen.
            spread: spot.spread,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
            paper: Self.paper(in: window), pageTurn: pageTurn, leafStyle: leafStyle
        )
    }

    /// The page's colour in the reader's theme, where a cover has left.
    private static func paper(in window: UIWindow) -> Color {
        let appearance = UserDefaults.standard.string(forKey: ReaderAppearance.key).flatMap(ReaderAppearance.init(rawValue:)) ?? ReaderAppearance()
        let darkMode = window.traitCollection.userInterfaceStyle == .dark
        return Color(hex: appearance.theme(darkMode: darkMode).background)
    }

    // MARK: The open book's sync

    /// Where the open book's bookmarks sync (decision 18): BookOrbit's own,
    /// for its books. Anything else keeps them on the iPhone.
    var bookmarkSync: (any BookmarkSync)? {
        guard let book = reading, let readingSource, let source = library.source(for: readingSource) as? BookOrbitSource,
              let bookID = Int(book.book.id.rawValue)
        else { return nil }
        return BookOrbitBookmarkSync(client: source.client, bookID: bookID, fileID: Int(book.file.id.rawValue))
    }

    /// Where the open book's place syncs (decision 6), through `places`, so
    /// the reader reuses the pull its screen just made.
    var progressSync: (any ProgressSync)? {
        readingBook.flatMap { places.readerSync(for: $0) }
    }

    /// The server's place for the open book as the library list gave it,
    /// where the reader opens if it can't pull.
    var listedPlace: SyncedPosition? {
        reading.flatMap { BookPlaces.listed($0.book) }
    }
}
