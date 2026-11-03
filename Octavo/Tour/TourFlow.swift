import Foundation
import OctavoKit
import UIKit

/// Where the tour for a new install is (decisions 29 and 30): the logic alone,
/// which the shell drives and the views draw.
///
/// Folded or without a fold the first steps drop out: step 1 asks to close an
/// iPhone that opened unfolded, step 2 is the cover, and without a fold it
/// starts in the book. The book's steps wait for the reader's own events, and
/// a fold closes the book, the step kept for the next unfold.
nonisolated struct TourFlow: Equatable, Sendable {
    nonisolated enum Step: Int, CaseIterable, Sendable {
        /// Close your iPhone, only if Octavo opened unfolded.
        case closeYourIPhone
        /// The cover, folded.
        case cover
        case welcome
        case turnThePage
        case bringUpControls
        /// Make it yours, with a ring on Aa.
        case tapAa
        /// Make it yours, with the Text and theme panel open.
        case makeItYours
        case addYourBooks
    }

    nonisolated enum Event: Equatable, Sendable {
        case folded
        case unfolded
        case continueWithoutClosing
        /// Welcome's Start.
        case start
        /// A page really turned: a swipe that falls back isn't one.
        case pageTurned
        /// The controls or the panels changed, or a step started.
        case reader(ReaderState)
        /// Make it yours' Done.
        case done
    }

    /// What a step in the book looks at.
    nonisolated struct ReaderState: Equatable, Sendable {
        var barVisible: Bool
        var buttonsVisible: Bool
        var textPanelOpen: Bool
    }

    private(set) var step: Step
    /// The step a fold left, which the next unfold goes back to.
    private(set) var resumes: Step?
    /// Played from Settings: the sample book opens without touching the
    /// shelf or its place.
    let isReplay: Bool

    /// `fold` is the hinge at the start, `nil` without one.
    init(fold: HingeTransition.Fold?, isReplay: Bool = false) {
        self.isReplay = isReplay
        step = switch fold {
        case .open?: .closeYourIPhone
        case .closed?: .cover
        case nil: .welcome
        }
    }

    /// The book is open at this step, or about to be.
    var isInBook: Bool { step.rawValue >= Step.welcome.rawValue }

    /// The cover's line: a book already opened goes on where it was.
    var coverLine: String {
        resumes == nil ? "Open your iPhone to begin" : "Open your iPhone to continue"
    }

    mutating func handle(_ event: Event) {
        switch (event, step) {
        case (.folded, .closeYourIPhone):
            step = .cover
        case (.folded, .cover):
            break
        case (.folded, _):
            resumes = step
            step = .cover
        case (.unfolded, .cover):
            step = resumes ?? .welcome
        case (.continueWithoutClosing, .closeYourIPhone):
            step = .welcome
        case (.start, .welcome):
            step = .turnThePage
        case (.pageTurned, .turnThePage):
            step = .bringUpControls
        case (.reader(let state), .bringUpControls):
            // Aa may already be open, from looking ahead: the bar goes while
            // a panel shows.
            if state.textPanelOpen {
                step = .makeItYours
            } else if state.barVisible {
                step = .tapAa
            }
        case (.reader(let state), .tapAa):
            if state.textPanelOpen {
                step = .makeItYours
            } else if !state.buttonsVisible {
                // A tap on the page hid them, and Aa with them.
                step = .bringUpControls
            }
        case (.done, .makeItYours):
            step = .addYourBooks
        default:
            break
        }
    }
}

extension TourFlow.Step {
    /// The card's words (decision 29).
    var card: (title: String, message: String)? {
        switch self {
        case .closeYourIPhone, .cover: nil
        case .welcome: ("Welcome to Octavo", "Try things out on this book. It’s yours to keep.")
        case .turnThePage: ("Turn the page", "Tap the right page, or swipe. Tap the left page to go back.")
        case .bringUpControls: ("Bring up the controls", "Tap ··· whenever you need them.")
        case .tapAa: ("Make it yours", "Tap Aa for themes, text size and fonts.")
        case .makeItYours: ("The page changes as you go", "Come back to Aa any time.")
        case .addYourBooks: ("Add your own books", "From your server, or from Files.")
        }
    }

    /// Which of the card's dots this step lights.
    var dot: Int {
        switch self {
        case .closeYourIPhone, .cover, .welcome: 0
        case .turnThePage: 1
        case .bringUpControls: 2
        case .tapAa, .makeItYours: 3
        case .addYourBooks: 4
        }
    }

    static let dotCount = 5

    /// What the pulsing ring marks.
    var ring: TourRingTarget? {
        switch self {
        case .turnThePage: .rightPage
        case .bringUpControls: .columnButton(ReaderColumnButton.showControls)
        case .tapAa: .columnButton(ReaderColumnButton.textAndTheme)
        default: nil
        }
    }

    /// The column's buttons stay up: this step started with them, and a
    /// reader reopened after a fold puts them back.
    var showsControlsOnOpening: Bool { self == .tapAa || self == .makeItYours }
}

nonisolated enum TourRingTarget: Equatable, Sendable {
    case rightPage
    case columnButton(String)
}

/// Whether the tour has played on this install. It plays once. Whether an
/// install is new is decided the first time the app runs at all, and kept:
/// iOS can run the app before anyone opens it (prewarming), which would leave
/// the install marker behind and make the first real launch look like a later
/// one. Unfinished, it starts again at the next launch, so someone who left at
/// step 1 still sees it. These defaults go with the app.
struct TourRecord {
    enum State: String {
        /// No sign of an earlier run: it plays at the next launch with a screen.
        case new
        case playing, played
    }

    static let key = "tour.state"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var state: State? {
        defaults.string(forKey: Self.key).flatMap(State.init(rawValue:))
    }

    func set(_ state: State) {
        defaults.set(state.rawValue, forKey: Self.key)
    }

    /// New or not, once. Before the install marker is set at launch
    /// (`OctavoApp`): an install that already has one has run before.
    func settle() {
        guard state == nil else { return }
        set(defaults.bool(forKey: ServerCredentials.installedKey) ? .played : .new)
    }

    /// `hasEarlierData`: a saved server or books, places and recents left by
    /// a build from before the marker. Before the iPhone's first unlock nothing
    /// can be read, so nothing is decided: the next launch asks again.
    func shouldPlay(hasEarlierData: Bool, protectedDataAvailable: Bool) -> Bool {
        guard protectedDataAvailable else { return false }
        settle()
        switch state {
        case .played?, nil:
            return false
        case .playing?:
            return true
        case .new?:
            if hasEarlierData { set(.played) }
            return !hasEarlierData
        }
    }
}

/// Where a tour replayed from Settings keeps its place and bookmarks, for as
/// long as it plays: temporary, so it starts at the book's start, and a fold
/// comes back to the same page, and nothing reaches the real ones.
nonisolated struct TourReplayPlace: Sendable {
    let directory: URL

    init(directory: URL = URL.temporaryDirectory.appending(path: "TourReplay-\(UUID().uuidString)", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    var positions: ReadingPositionStore {
        ReadingPositionStore(directory: directory.appending(path: "ReadingPositions", directoryHint: .isDirectory))
    }

    var bookmarks: BookmarkStore {
        BookmarkStore(directory: directory.appending(path: "Bookmarks", directoryHint: .isDirectory))
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
