import Foundation
import Observation
import OctavoKit

/// The shell's state: the selected tab, each tab's open screens and the
/// shared states. It lives with the scene, which folding or unfolding moves
/// between displays without rebuilding (`docs/notes/duo-spreads.md` §6), so
/// a fold keeps the same screens.
@Observable
final class ShellModel {
    var tab: ShellTab = .home
    // One property per tab, so navigating in one tab doesn't redraw the others.
    // Home's and the Library's companions follow what they show (decision 26).
    private var homePath = PanePath()
    private var libraryPath = PanePath()
    private var settingsPath = PanePath(companion: .settingsPage("BookOrbit"))
    private var searchPath = PanePath()

    /// The books, and where they come from.
    let library: LibraryModel
    /// The book open in the reader, which covers the tabs (frames 07–09).
    var reading: OpenedBook? {
        didSet {
            if let closed = oldValue, closed != reading {
                pages.existingPage(for: closed.book.id)?.readerClosed()
                library.mergeContinueReading()
            }
        }
    }
    /// Downloads books and opens them in `reading` (#14).
    let opener: BookOpener
    /// The library of each book asked to open, until it does.
    private var opening: [LibraryBookID: LibrarySourceID] = [:]
    /// The cover pages' state, kept across folds.
    let pages = BookPages()

    /// A debug override for the cover's strip (frames 23, 24, 42), to look
    /// at its states without a failing download.
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
            for tab in [ShellTab.home, .library, .search] { self[path: tab].routes = [] }
        }
        #if DEBUG
        applyLaunchArguments()
        #endif
    }

    subscript(path tab: ShellTab) -> PanePath {
        get {
            switch tab {
            case .home: homePath
            case .library: libraryPath
            case .settings: settingsPath
            case .search: searchPath
            }
        }
        set {
            switch tab {
            case .home: homePath = newValue
            case .library: libraryPath = newValue
            case .settings: settingsPath = newValue
            case .search: searchPath = newValue
            }
        }
    }

    /// Opens `route` from the pane `pane` describes: pushed folded,
    /// beside it or shifted along unfolded.
    func open(_ route: ShellRoute, from pane: PaneContext) {
        if let level = pane.level {
            self[path: pane.tab].open(route, from: level)
        } else {
            self[path: pane.tab].routes.append(route)
        }
    }

    /// Opens `book` in the reader, downloading it first if it isn't on the
    /// iPhone yet (decision 3; the cover's strip shows the progress), and
    /// once it opens puts it first in Home's Continue reading.
    func openBook(_ book: SourcedBook) {
        guard let source = library.source(for: book.source), opener.canOpen(book.book) else { return }
        opening[book.book.id] = book.source
        opener.open(book.book, from: source)
    }

    /// Only a book that reaches the reader joins Continue reading: not one
    /// whose download failed or was cancelled.
    private func opened(_ book: OpenedBook) {
        if let source = opening.removeValue(forKey: book.book.id) {
            library.bookOpened(SourcedBook(source: source, book: book.book))
        }
        reading = book
    }

    /// Unfolding on a book's cover opens the book at once (decision 4);
    /// anywhere else the screen stays and takes its unfolded layout
    /// (decision 10). The hinge reports the unfold before the scene moves to
    /// the inner display, so the folded screen is still the deepest route.
    func hingeChanged(_ transition: HingeTransition) {
        guard transition == .unfold, reading == nil,
              let book = self[path: tab].routes.last?.bookOpenedOnUnfold
        else { return }
        openBook(book)
    }

    #if DEBUG
    /// Launch arguments that set up a state to look at:
    /// `-connectBookOrbit 1` (the local server), `-sampleLibrary 1|empty`
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
        let opens = defaults.string(forKey: "shellOpen")
        let reads = defaults.bool(forKey: "shellReading")
        Task {
            if connectsBookOrbit {
                await library.connectLocalBookOrbit()
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
            case "collection": self[path: .library].routes = [classics]
            case "deep": self[path: .library].routes = [classics, .cover(book)]
            case "cover": self[path: .library].routes = [.cover(book)]
            case "settings": self[path: .settings].routes = [.settingsPage("BookOrbit")]
            default: break
            }
            if reads, let first = library.continueReading.first {
                openBook(first)
            }
        }
    }
    #endif
}
