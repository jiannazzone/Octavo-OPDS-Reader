import Foundation
import Observation

/// The shell's state: the selected tab, each tab's open screens and the
/// shared states. It lives with the scene, which folding or unfolding moves
/// between displays without rebuilding (`docs/notes/duo-spreads.md` §6), so
/// a fold keeps the same screens.
@Observable
final class ShellModel {
    var tab: ShellTab = .home
    // One property per tab, so navigating in one tab doesn't redraw the others.
    private var homePath = PanePath(companion: .cover(PlaceholderBook.samples[0]))
    private var libraryPath = PanePath(companion: .cover(PlaceholderBook.samples[0]))
    private var settingsPath = PanePath(companion: .settingsPage("BookOrbit"))
    private var searchPath = PanePath()

    /// Shown as a banner at the top of the tabs (decision 22).
    var connectionProblem: ConnectionProblem?
    /// The book open in the reader, which covers the tabs (frames 07–09).
    var reading: PlaceholderBook?

    /// Stand-in states until the real sources exist: an empty Home
    /// (frame 25) and a problem on the cover's strip (frames 23, 24, 42).
    var homeIsEmpty = false {
        didSet { self[path: .home].companion = homeIsEmpty ? nil : .cover(PlaceholderBook.samples[0]) }
    }
    var coverStrip: CoverStripMessage?

    #if DEBUG
    /// The spike's screens, kept reachable from the Library until #13.
    var showsSpike = false
    #endif

    init() {
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

    func openBook(_ book: PlaceholderBook) {
        reading = book
    }

    /// Unfolding on a book's cover opens the book at once (decision 4);
    /// anywhere else the screen stays and takes its unfolded layout
    /// (decision 10). The hinge reports the unfold before the scene moves to
    /// the inner display, so the folded screen is still the deepest route.
    func hingeChanged(_ transition: HingeTransition) {
        guard transition == .unfold, reading == nil, !isCoveredBySpike,
              let book = self[path: tab].routes.last?.bookOpenedOnUnfold
        else { return }
        openBook(book)
    }

    /// The spike's screens hide the tabs and do their own unfold handoff.
    private var isCoveredBySpike: Bool {
        #if DEBUG
        showsSpike
        #else
        false
        #endif
    }

    /// Retry or Sign in on the connection banner. A stand-in until #7 and #9.
    func resolveConnectionProblem() {
        connectionProblem = nil
    }

    #if DEBUG
    /// Launch arguments that set up a state to look at:
    /// `-shellTab library`, `-shellConnection unreachable|signedOut`,
    /// `-shellEmptyHome 1`, `-shellCoverStrip failed|offline|downloading`,
    /// `-shellOpen collection|deep|cover|settings`, `-shellReading 1`.
    private func applyLaunchArguments() {
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "shellTab").flatMap(ShellTab.init(rawValue:)) {
            self.tab = tab
        }
        switch defaults.string(forKey: "shellConnection") {
        case "unreachable": connectionProblem = .unreachable(server: "BookOrbit")
        case "signedOut": connectionProblem = .signedOut(server: "BookOrbit")
        default: break
        }
        homeIsEmpty = defaults.bool(forKey: "shellEmptyHome")
        switch defaults.string(forKey: "shellCoverStrip") {
        case "failed": coverStrip = .downloadFailed
        case "offline": coverStrip = .needsConnection
        case "downloading": coverStrip = .downloading(fraction: 0.42)
        default: break
        }
        let book = PlaceholderBook.samples[0]
        switch defaults.string(forKey: "shellOpen") {
        case "collection": self[path: .library].routes = [.collections, .collection("Classics")]
        case "deep": self[path: .library].routes = [.collections, .collection("Classics"), .cover(book)]
        case "cover": self[path: .library].routes = [.cover(book)]
        case "settings": self[path: .settings].routes = [.settingsPage("BookOrbit")]
        default: break
        }
        if defaults.bool(forKey: "shellReading") {
            reading = book
        }
    }
    #endif
}
