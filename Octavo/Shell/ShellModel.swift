import Foundation
import Observation
import OctavoKit

/// The shell's state: the selected tab, each tab's screens and the shared
/// states. It lives with the scene, which folding or unfolding moves between
/// displays without rebuilding (`docs/notes/duo-spreads.md` §6), so a fold
/// keeps the same screens.
@Observable
final class ShellModel {
    private(set) var tab: ShellTab = .home
    // One property per tab, so navigating in one tab doesn't redraw the others.
    private var homePath = ShellPath()
    private var libraryPath = ShellPath()
    private var searchPath = ShellPath()

    /// The books, and where they come from.
    let library: LibraryModel
    /// The book open in the reader, which covers the tabs.
    var reading: OpenedBook? {
        didSet {
            if let closed = oldValue, closed != reading {
                pages.existingPage(for: closed.book.id)?.readerClosed()
                library.mergeContinueReading()
            }
        }
    }
    /// The library of the book in the reader, for its screen when a fold
    /// closes it.
    private var readingSource: LibrarySourceID?
    /// Downloads books and opens them in `reading`.
    let opener: BookOpener
    /// The library of each book asked to open, until it does.
    private var opening: [LibraryBookID: LibrarySourceID] = [:]
    /// The book screens' state, kept across folds.
    let pages = BookPages()

    /// A debug override for the cover's strip, to look at its states without
    /// a failing download.
    var coverStrip: CoverStripMessage?

    init(library: LibraryModel = LibraryModel(), opener: BookOpener = BookOpener()) {
        self.library = library
        self.opener = opener
        opener.onOpen = { [weak self] in self?.opened($0) }
        // Another server: its books' pages and the screens opened from
        // them go.
        library.serverChanged = { [weak self] in
            guard let self else { return }
            pages.removeAll()
            for tab in ShellTab.allCases { self[path: tab].replace([]) }
        }
        #if DEBUG
        applyLaunchArguments()
        #endif
    }

    subscript(path tab: ShellTab) -> ShellPath {
        get {
            switch tab {
            case .home: homePath
            case .library: libraryPath
            case .search: searchPath
            }
        }
        set {
            switch tab {
            case .home: homePath = newValue
            case .library: libraryPath = newValue
            case .search: searchPath = newValue
            }
        }
    }

    // MARK: Navigation

    /// Choosing the tab that's showing goes back to its root, as iOS does.
    func select(_ tab: ShellTab) {
        if tab == self.tab {
            self[path: tab].popToRoot()
        } else {
            self.tab = tab
        }
    }

    /// Opens `route` on top of the current tab.
    func push(_ route: ShellRoute) {
        self[path: tab].push(route)
    }

    /// Back.
    func pop(_ tab: ShellTab) {
        self[path: tab].pop()
    }

    func popToRoot(_ tab: ShellTab) {
        self[path: tab].popToRoot()
    }

    /// The Settings button at the top of the side column.
    func openSettings() {
        push(.settings)
    }

    // MARK: Books

    /// Opens `book` in the reader, downloading it first if it isn't on the
    /// iPhone yet, and once it opens puts it first in Continue reading.
    func openBook(_ book: SourcedBook) {
        guard let source = library.source(for: book.source), opener.canOpen(book.book) else { return }
        opening[book.book.id] = book.source
        opener.open(book.book, from: source)
    }

    /// Only a book that reaches the reader joins Continue reading: not one
    /// whose download failed or was cancelled.
    private func opened(_ book: OpenedBook) {
        let source = opening.removeValue(forKey: book.book.id)
        if let source {
            library.bookOpened(SourcedBook(source: source, book: book.book))
        }
        readingSource = source
        reading = book
    }

    /// The Duo as the book:
    /// - Unfolding on a book's screen opens the book, if it's on the iPhone.
    ///   If it isn't, the screen stays, as Cover | Details, and nothing
    ///   downloads until Download or Open is tapped.
    /// - Folding while reading closes the book back to its screen.
    ///
    /// The hinge reports an unfold before the scene moves to the inner
    /// display, so the folded screen is still the top one.
    func hingeChanged(_ transition: HingeTransition) {
        switch transition {
        case .unfold:
            guard reading == nil, case .cover(let book)? = self[path: tab].top,
                  opener.status(of: book.book) == .downloaded
            else { return }
            openBook(book)
        case .fold:
            guard let book = reading else { return }
            closeToItsScreen(book)
        case .none:
            break
        }
    }

    /// Closes the reader onto `book`'s screen, opening that screen if the
    /// book was opened from somewhere else (Home's debug launch argument).
    private func closeToItsScreen(_ book: OpenedBook) {
        reading = nil
        guard let source = readingSource else { return }
        if case .cover(let shown)? = self[path: tab].top, shown.book.id == book.book.id { return }
        self[path: tab].replace(self[path: tab].routes + [.cover(SourcedBook(source: source, book: book.book))])
    }

    #if DEBUG
    /// Launch arguments that set up a state to look at:
    /// `-connectBookOrbit 1` (the local server),
    /// `-connectOPDS calibreWeb|cops|komga|komga2|kavita` (`dev/opds/`),
    /// `-sampleLibrary 1|empty`
    /// (made-up books; `empty` has nothing in progress), `-shellTab library`,
    /// `-shellConnection unreachable|signedOut`,
    /// `-shellCoverStrip failed|offline|downloading`,
    /// `-shellOpen collection|deep|cover|settings` (sample books) and
    /// `-shellReading 1` (the first book in Continue reading, once connected).
    private func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "shellTab").flatMap(ShellTab.init(rawValue:)) {
            self.tab = tab
        }
        let problem: ConnectionProblem? = switch defaults.string(forKey: "shellConnection") {
        case "unreachable": .unreachable(server: "BookOrbit")
        case "signedOut": .signedOut(server: "BookOrbit")
        default: nil
        }
        switch defaults.string(forKey: "shellCoverStrip") {
        case "failed": coverStrip = .downloadFailed
        case "offline": coverStrip = .needsConnection
        case "downloading": coverStrip = .downloading(fraction: 0.42)
        default: break
        }
        let sample = defaults.string(forKey: "sampleLibrary")
        let connectsBookOrbit = defaults.bool(forKey: "connectBookOrbit")
        let opds = defaults.string(forKey: "connectOPDS").flatMap(LibraryModel.DebugOPDSServer.init(rawValue:))
        let opens = defaults.string(forKey: "shellOpen")
        let reads = defaults.bool(forKey: "shellReading")
        Task {
            if connectsBookOrbit {
                await library.connectLocalBookOrbit()
            } else if let opds {
                await library.connectLocalOPDS(opds)
            } else if let sample, sample != "0" {
                await library.connectSampleLibrary(nothingInProgress: sample == "empty")
            }
            // After connecting, which closes the screens opened before it.
            if let problem { library.connectionProblem = problem }
            let book = SourcedBook(source: SampleLibrarySource.id, book: SampleLibrarySource.books[0])
            let classics = ShellRoute.feed(
                LibraryEntry(kind: .collection, title: "Classics", count: 5, link: LibraryLink(rawValue: "collections/classics")),
                from: SampleLibrarySource.id
            )
            switch opens {
            case "collection": self[path: .library].replace([classics])
            case "deep": self[path: .library].replace([classics, .cover(book)])
            case "cover": self[path: .library].replace([.cover(book)])
            case "settings": self[path: tab].replace([.settings])
            default: break
            }
            if reads, let first = library.continueReading.first {
                openBook(first)
            }
        }
    }
    #endif
}
