import Foundation

/// A footnote opens where you are (decision 34). It isn't a jump: the page
/// doesn't move, so nothing is saved or sent. Go to Note is one (decision 33).
extension ReaderModel {
    /// A note's mark was tapped. Over the page's other things, and with a note
    /// open a tap on anything only closes it. Under a fold or a turn the page
    /// isn't settled, and another tap will do.
    func noteTapped(_ tapped: ReaderNote) {
        guard note == nil else { return closeNote() }
        guard !isFolding, turnRun == nil else { return }
        onControlsTap?("dismiss")
        note = tapped
    }

    func closeNote() {
        note = nil
    }

    /// Where the note sits in the book, with the way back to here.
    func goToNote() {
        guard let href = note?.href else { return }
        closeNote()
        jump(to: href)
    }

    /// A swipe on the card closes it and turns, as one on the page does.
    func noteSwiped(_ side: ReaderTurnSide) {
        closeNote()
        turnRequested(side)
    }
}
