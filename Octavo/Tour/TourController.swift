import Foundation
import Observation
import OctavoKit
import SwiftUI
import UIKit

/// A new install's tour, and its replay from Settings (decisions 29 and 30):
/// when it starts, what the hinge and the reader do to its steps, and how it
/// ends. While it plays it covers the tabs: `TourScreen` for its first two
/// steps, the reader with its card for the rest. The shell owns it, and lends
/// it the reader and the sample book (`docs/notes/ui-audit.md`, item 4).
@Observable
final class TourController {
    /// The tour, while it plays.
    private(set) var playing: TourFlow?
    /// A new install's first launch, until the hinge says how the tour starts.
    private(set) var waitsForHinge = false
    /// A replay's place, so it never touches the book's (`TourReplayPlace`).
    private(set) var replayPlace: TourReplayPlace?
    /// The hinge as last reported, `nil` while it's said nothing.
    @ObservationIgnored private var hingeFold: HingeTransition.Fold?
    @ObservationIgnored private var hingeIsSilent = false

    /// Playing, or waiting for the hinge to start: either way it covers the
    /// tabs, and setup waits.
    var isActive: Bool { playing != nil || waitsForHinge }

    /// The sample book on the shelf, copied there if it isn't
    /// (`ShellModel.installSampleBook`): `nil` with no room for it.
    @ObservationIgnored var installSampleBook: () -> SourcedBook? = { nil }
    /// A new install's tour is over: the sample book first in Continue
    /// reading, and Home if the tour itself ended (not an import, which goes
    /// to the Library).
    @ObservationIgnored var played: (_ landsOnHome: Bool) -> Void = { _ in }
    /// A replay ended: back to the Settings it was shown from.
    @ObservationIgnored var replayEnded: () -> Void = {}
    /// Files are coming in: a new install opened with one waits to see
    /// whether it arrives.
    @ObservationIgnored var isImporting: () -> Bool = { false }

    /// Whether a new install's tour has played (decision 30).
    private let record: TourRecord
    private let reader: ReaderPresenter

    init(record: TourRecord, reader: ReaderPresenter) {
        self.record = record
        self.reader = reader
    }

    // MARK: Starting

    /// Whether this launch plays the tour: a new install (`TourRecord`), or
    /// one that didn't finish it. `hasEarlierData`: anything an earlier
    /// install left.
    func prepare(hasEarlierData: Bool) {
        #if DEBUG
        guard !debugLaunchSkips else { return }
        #endif
        waitsForHinge = record.shouldPlay(
            hasEarlierData: hasEarlierData, protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable
        )
    }

    /// Every report from the hinge (`onHingeChange` fires once on appear): the
    /// first with a hinge says how a new install's tour starts. After that the
    /// tour follows it, even if the change itself was never reported, as when
    /// the iPhone was opened or closed while the app was away.
    func hingeReported(_ fold: HingeTransition.Fold?) {
        guard let fold else { return }
        #if DEBUG
        guard !UserDefaults.standard.bool(forKey: "tourNoFold") else { return }
        #endif
        hingeFold = fold
        if let step = playing?.step {
            if fold == .open, step == .cover {
                hingeChanged(.unfold)
            } else if fold == .closed, step != .cover {
                hingeChanged(.fold)
            }
        }
        startIfHingeKnown()
    }

    /// The hinge hasn't said anything by now: this iPhone has no fold.
    func hingeStayedSilent() {
        hingeIsSilent = true
        startIfHingeKnown()
    }

    /// Not while a file is coming in: opened with one, the tour waits to see
    /// whether it arrives (`ShellModel.importBooks`, which asks again once
    /// it's in).
    func startIfHingeKnown() {
        guard waitsForHinge, !isImporting() else { return }
        if let hingeFold {
            start(fold: hingeFold)
        } else if hingeIsSilent {
            start(fold: nil)
        }
    }

    private func start(fold: HingeTransition.Fold?) {
        waitsForHinge = false
        record.set(.playing)
        guard installSampleBook() != nil else {
            // Nothing to teach with (no room for its copy): setup for now,
            // and the next launch tries again.
            record.set(.new)
            return
        }
        begin(TourFlow(fold: fold))
    }

    /// Show the tour, in Settings: from the beginning, and back to Settings.
    func show() {
        guard playing == nil, reader.reading == nil else { return }
        let place = TourReplayPlace()
        SampleBook.startAtFirstChapter(in: place.positions)
        replayPlace = place
        begin(TourFlow(fold: hingeFold, isReplay: true))
    }

    private func begin(_ flow: TourFlow) {
        playing = flow
        if flow.isInBook { openBook() }
    }

    /// The sample book for the tour. A new install's is the one on the shelf,
    /// through the library, so it joins Continue reading. A replay's is the
    /// app's own copy with nowhere to save its place: nothing goes back on the
    /// shelf if it was removed, and no place moves if it wasn't.
    private func openBook(_ opening: ReaderPresenter.Opening = .tapped) {
        if playing?.isReplay == true {
            guard let url = SampleBook.bundledFile, let file = SampleBook.book.primaryFile else { return finish() }
            reader.open(copy: OpenedBook(book: SampleBook.book, source: .files, file: file, url: url), opening)
        } else if let sample = installSampleBook() {
            reader.open(sample, opening)
        } else {
            finish()
        }
    }

    // MARK: Playing

    /// One of the reader's events, or a card's Start or Done.
    func handle(_ event: TourFlow.Event) {
        playing?.handle(event)
    }

    /// Mid-tour a fold closes the book, as always, and the step waits on the
    /// cover; unfolding on the cover opens the book at that step. Close book
    /// when folded doesn't apply.
    ///
    /// Either way a cover opening or closing the book goes, as outside the
    /// tour (`ShellModel.hingeChanged`): this also hears a change made while
    /// the app was away (`hingeReported`).
    func hingeChanged(_ transition: HingeTransition) {
        if transition != .none { reader.coverMotion = nil }
        switch transition {
        case .fold:
            reader.close { playing?.handle(.folded) }
        case .unfold:
            guard playing?.step == .cover else { return }
            playing?.handle(.unfolded)
            openBook(.unfolded)
        case .none:
            break
        }
    }

    /// Continue without closing: the cover at `coverFrame` (in the window)
    /// opens the book as a book's screen does (decision 28). No left page to
    /// start from, and the reader fades in.
    func continueWithoutClosing(coverFrame: CGRect?) {
        guard playing?.step == .closeYourIPhone else { return }
        // Taken before the step changes the screen.
        let motion = coverFrame.flatMap(reader.sampleCoverMotion(from:))
        playing?.handle(.continueWithoutClosing)
        openBook(motion.map { .motion($0) } ?? .tapped)
    }

    // MARK: Ending

    /// Skip, on any tour screen, or Not now on the last card: Home with the
    /// sample book under Continue reading; replayed, back to Settings. Add
    /// books and an import end it this way too.
    func finish() {
        guard let finished = playing else { return }
        end()
        guard !finished.isReplay else { return replayEnded() }
        record.set(.played)
        played(true)
    }

    /// Takes the tour away: the reader closes at once with any cover's
    /// motion, and a replay's place goes.
    private func end() {
        reader.coverMotion = nil
        reader.close { playing = nil }
        replayPlace?.clear()
        replayPlace = nil
    }

    /// Files came in: they're what the tour gives way to. Opened with them on
    /// a new install, they're what they came for (Adam, 2026-11-03): the tour
    /// counts as played, and the sample book is there all the same.
    func endForImport() {
        if waitsForHinge {
            waitsForHinge = false
            record.set(.played)
            played(false)
        }
        finish()
    }

    #if DEBUG
    /// A launch argument setting up a state to look at means someone's
    /// checking something else, on what may be a fresh install.
    private var debugLaunchSkips: Bool {
        let defaults = UserDefaults.standard
        // The test host isn't a new install, whatever its simulator says. Tests
        // of the tour pass a record of their own.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil, record.defaults === defaults { return true }
        return ["connectBookOrbit", "connectOPDS", "sampleLibrary", "shellOpen", "shellReading", "shellTab", "shellConnection",
                "shellCoverStrip", "searchQuery", "forgetServer", "setupCatalog"]
            .contains { defaults.object(forKey: $0) != nil }
    }

    /// The debug remote's reader commands: scripts check something else, on
    /// what may be a fresh install.
    func debugEnd() {
        guard isActive else { return }
        waitsForHinge = false
        record.set(.played)
        end()
    }

    /// For the remote: where the tour is.
    var debugState: String {
        guard let playing else { return waitsForHinge ? "waiting for the hinge" : "none, record \(record.state?.rawValue ?? "nil")" }
        return "\(playing.step) resumes \(String(describing: playing.resumes)) replay \(playing.isReplay) reading \(reader.reading != nil)"
    }
    #endif
}
