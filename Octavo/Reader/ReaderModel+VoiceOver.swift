import UIKit

/// VoiceOver (#74) and Voice Control (#75), `docs/notes/accessibility.md`.
/// VoiceOver reads the page as one item (`ReaderVoiceOverPage`). A
/// three-finger swipe sideways turns the page as a tap on that side does,
/// with the same motion, and so does Read All at the end of a page;
/// VoiceOver then says where it landed, "Page 12 of 547 · 2%", and reads on.
/// Without VoiceOver, Next Page and Previous Page turn it.
extension ReaderModel {
    /// Returns whether a turn was asked for; VoiceOver plays its "can't"
    /// sound when not. Not with a note open (its card is over the page, and
    /// the turn would only close it) or with turns already queued to the
    /// limit, which would drop it.
    @discardableResult
    func accessibilityTurn(_ side: ReaderTurnSide) -> Bool {
        guard phase == .open, !isFolding, note == nil, queuedTurns.count < Self.mostQueuedTurns,
              relocation?.turns(side) != false else { return false }
        voiceOverTurns.asked(at: .now)
        turnRequested(side)
        return true
    }

    /// The turn that reads on: forward in the book's own direction.
    var forwardSide: ReaderTurnSide { readsRightToLeft ? .left : .right }

    /// Says the new place if it's where one of VoiceOver's turns landed. Said
    /// a moment later, once the page's item has its new words: VoiceOver
    /// reads them next.
    func announceVoiceOverTurn(_ relocation: ReaderMessage.Relocation) {
        guard voiceOverTurns.landed(at: .now, byJump: jumpsUnderWay > 0 || isGoingBack) else { return }
        let place = ReaderPlace(chapter: relocation.tocLabel, location: relocation.location, fraction: relocation.shownFraction)
            .barLine(spread: layout.columns == 2)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            UIAccessibility.post(notification: .pageScrolled, argument: place)
        }
    }
}

/// VoiceOver's page turns on their way, to say where each lands: quick
/// turns queue, and each is said, so the last place heard is the last
/// landed. A jump or going back meanwhile isn't one of them; it ends them,
/// as does a turn that hasn't landed in 3 s.
nonisolated struct ReaderVoiceOverTurns {
    static let landsWithin: Duration = .seconds(3)
    private var toLand = 0
    private var askedAt: ContinuousClock.Instant?

    mutating func asked(at now: ContinuousClock.Instant) {
        if let askedAt, now - askedAt >= Self.landsWithin { toLand = 0 }
        toLand += 1
        askedAt = now
    }

    /// Whether the page moved for one of the turns, to be said.
    mutating func landed(at now: ContinuousClock.Instant, byJump: Bool) -> Bool {
        guard toLand > 0, let askedAt else { return false }
        guard !byJump, now - askedAt < Self.landsWithin else {
            toLand = 0
            return false
        }
        toLand -= 1
        return true
    }
}
