import SwiftUI
import UIKit

/// The page as VoiceOver reads it, one item (#74, Adam 2026-11-14;
/// `docs/notes/accessibility.md`): the words on the page, from `bridge.js`,
/// in place of the book's own text, which runs on past the page and never
/// hears VoiceOver's page turns. A three-finger swipe turns the page, and at
/// the end of a page Read All turns it and reads on (`ReaderModel+VoiceOver`).
/// A double tap shows or hides the controls, as "…" does. Nothing to see or
/// touch: taps reach the page under it.
///
/// UIKit, because SwiftUI's scroll action hands Read All's "next" over as
/// the same edge as a swipe toward the left page, so it would read backwards.
struct ReaderVoiceOverPage: UIViewRepresentable {
    let model: ReaderModel
    let toggleControls: () -> Void

    func makeUIView(context: Context) -> PageView {
        PageView()
    }

    func updateUIView(_ view: PageView, context: Context) {
        view.accessibilityLabel = model.pageWords ?? place
        view.turn = { [model] direction in
            guard let side = Self.side(for: direction, forward: model.forwardSide) else { return false }
            return model.voiceOverTurn(side)
        }
        view.activate = toggleControls
    }

    /// A page with no words (a picture) says where it is.
    private var place: String {
        ReaderPlace(chapter: model.chapter, location: model.location, fraction: model.shownFraction)
            .barLine(spread: model.layout.columns == 2)
    }

    /// The page to turn to for VoiceOver's scroll: sideways by the page's own
    /// sides (a three-finger swipe left shows the right page), and up, down,
    /// next and previous through the book, as Read All goes on.
    nonisolated static func side(for direction: UIAccessibilityScrollDirection, forward: ReaderTurnSide) -> ReaderTurnSide? {
        switch direction {
        case .right: .right
        case .left: .left
        case .down, .next: forward
        case .up, .previous: forward.opposite
        @unknown default: nil
        }
    }

    final class PageView: UIView {
        var turn: (UIAccessibilityScrollDirection) -> Bool = { _ in false }
        var activate: () -> Void = {}

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityTraits = .causesPageTurn
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
            turn(direction)
        }

        override func accessibilityActivate() -> Bool {
            activate()
            return true
        }
    }
}
