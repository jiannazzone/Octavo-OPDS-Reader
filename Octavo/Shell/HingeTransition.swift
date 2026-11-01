import SwiftUI

/// What one `onHingeChange` callback means for the shell.
///
/// `onHingeChange` fires once on appear (from no hinge) and then repeats
/// unchanged values for about half a second after each move
/// (`docs/notes/duo-spreads.md` §1), so only a change between closed and
/// open counts. Half open and fully open are both open: going between them
/// doesn't move the scene.
nonisolated enum HingeTransition: Equatable, Sendable {
    case unfold
    case fold
    case none

    nonisolated enum Fold: Equatable, Sendable {
        case closed
        case open
    }

    init(from old: Fold?, to new: Fold?) {
        switch (old, new) {
        case (.closed?, .open?): self = .unfold
        case (.open?, .closed?): self = .fold
        default: self = .none
        }
    }

    init(from old: DeviceHingeContext, to new: DeviceHingeContext) {
        self.init(from: Fold(old.hinge?.status), to: Fold(new.hinge?.status))
    }
}

nonisolated extension HingeTransition.Fold {
    init?(_ status: DeviceHinge.Status?) {
        switch status {
        case .closed?: self = .closed
        case .partiallyOpen?, .fullyOpen?: self = .open
        default: return nil
        }
    }
}
