import UIKit

/// VoiceOver (#74, `docs/notes/accessibility.md`). VoiceOver reads the page
/// as one item (`ReaderVoiceOverPage`). A three-finger swipe sideways turns
/// the page as a tap on that side does, with the same motion, and so does
/// Read All at the end of a page; VoiceOver then says where it landed,
/// "Page 12 of 547 · 2%", and reads on.
extension ReaderModel {
    /// Returns whether a turn was asked for; VoiceOver plays its "can't"
    /// sound when not.
    @discardableResult
    func voiceOverTurn(_ side: ReaderTurnSide) -> Bool {
        guard phase == .open, !isFolding, relocation?.turns(side) != false else { return false }
        voiceOverTurnedAt = .now
        turnRequested(side)
        return true
    }

    /// The turn that reads on: forward in the book's own direction.
    var forwardSide: ReaderTurnSide { readsRightToLeft ? .left : .right }

    /// Says the new place, once, if VoiceOver turned to it. A turn at the
    /// book's end moves nothing, so a later move isn't taken for it. Said a
    /// moment later, once the page's item has its new words: VoiceOver reads
    /// them next.
    func announceVoiceOverTurn(_ relocation: ReaderMessage.Relocation) {
        guard let turnedAt = voiceOverTurnedAt else { return }
        voiceOverTurnedAt = nil
        guard ContinuousClock.now - turnedAt < .seconds(3) else { return }
        let place = ReaderPlace(chapter: relocation.tocLabel, location: relocation.location, fraction: relocation.shownFraction)
            .barLine(spread: layout.columns == 2)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            UIAccessibility.post(notification: .pageScrolled, argument: place)
        }
    }
}
