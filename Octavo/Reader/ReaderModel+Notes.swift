import Foundation

/// A footnote opens where you are (decision 34). It isn't a jump: the page
/// doesn't move, so nothing is saved or sent. Go to Note is one (decision 33).
extension ReaderModel {
    /// How long after a note opens another report of its mark is the same tap.
    static let sameTapWindow = Duration.milliseconds(500)

    /// A note's mark was tapped. Over the page's other things, and with a note
    /// open a tap on anything only closes it. Under a fold or a turn the page
    /// isn't settled, and another tap will do.
    func noteTapped(_ tapped: ReaderNote) {
        if let note {
            // A near miss can be reported twice, by the touch and by WebKit's click.
            if note.href == tapped.href, let noteOpenedAt, ContinuousClock.now - noteOpenedAt < Self.sameTapWindow { return }
            return closeNote("another mark")
        }
        guard !isFolding, turnRun == nil else { return }
        onControlsTap?("dismiss")
        note = tapped
        noteOpenedAt = .now
        #if DEBUG
        DebugEvents.log("note opened", ["href": tapped.href])
        #endif
    }

    /// `why` is for the debug log.
    func closeNote(_ why: String = "the card") {
        guard note != nil else { return }
        #if DEBUG
        DebugEvents.log("note closed", ["why": why])
        #endif
        note = nil
    }

    /// Where the note sits in the book, with the way back to here.
    func goToNote() {
        guard let href = note?.href else { return }
        closeNote("Go to Note")
        jump(to: href)
    }

    /// A swipe on the card closes it and turns, as one on the page does.
    func noteSwiped(_ side: ReaderTurnSide) {
        closeNote("a swipe on the card")
        turnRequested(side)
    }
}
