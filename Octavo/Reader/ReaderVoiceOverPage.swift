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
/// Without VoiceOver, Next Page and Previous Page sit over the page's sides
/// (#75, Adam 2026-11-14): Voice Control's "Swipe left" never turned it, and
/// Switch Control has no page turn of its own.
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
        view.page.accessibilityLabel = model.pageWords ?? place
        view.turn = { [model] side in model.accessibilityTurn(side) }
        view.forward = model.forwardSide
        if let inset = model.geometry?.safeArea {
            view.safeArea = UIEdgeInsets(top: inset.top, left: inset.left, bottom: inset.bottom, right: inset.right)
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

    /// Holds the page's item and, without VoiceOver, the two turn buttons.
    final class PageView: UIView {
        /// Turns to that side; whether it could.
        var turn: (ReaderTurnSide) -> Bool = { _ in false }
        var activate: () -> Void = {}
        /// The side forward is on, where Next Page sits.
        var forward: ReaderTurnSide = .right {
            didSet { if forward != oldValue { nameButtons() } }
        }
        /// The page runs under the side column (decision 8). The buttons
        /// stay out of it: Voice Control leaves out a button whose middle is
        /// under something else, as Next Page's was folded.
        var safeArea = UIEdgeInsets.zero {
            didSet { if safeArea != oldValue { setNeedsLayout() } }
        }
        /// The share of the visible page's width each button covers, at its
        /// side.
        static let buttonShare: CGFloat = 0.25

        private(set) var page: Element!
        private var buttons: [ReaderTurnSide: Element] = [:]

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            page = Element(accessibilityContainer: self)
            page.accessibilityTraits = .causesPageTurn
            // Voice Control's name for it: its label is the whole page.
            page.accessibilityUserInputLabels = [String(localized: "Page")]
            page.scrolled = { [unowned self] direction in
                guard let side = ReaderVoiceOverPage.side(for: direction, forward: forward) else { return false }
                return turn(side)
            }
            page.activated = { [unowned self] in
                activate()
                return true
            }
            for side in [ReaderTurnSide.left, .right] {
                let button = Element(accessibilityContainer: self)
                button.accessibilityTraits = .button
                button.activated = { [unowned self] in turn(side) }
                buttons[side] = button
            }
            nameButtons()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// VoiceOver turns with three fingers, so it gets the page alone.
        override var accessibilityElements: [Any]? {
            get {
                guard !UIAccessibility.isVoiceOverRunning, let left = buttons[.left], let right = buttons[.right] else { return [page!] }
                return [left, page!, right]
            }
            set {}
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            page.accessibilityFrameInContainerSpace = bounds
            let visible = bounds.inset(by: safeArea)
            let width = (visible.width * Self.buttonShare).rounded()
            buttons[.left]?.accessibilityFrameInContainerSpace = CGRect(x: visible.minX, y: visible.minY, width: width, height: visible.height)
            buttons[.right]?.accessibilityFrameInContainerSpace = CGRect(x: visible.maxX - width, y: visible.minY, width: width, height: visible.height)
        }

        private func nameButtons() {
            buttons[forward]?.accessibilityLabel = String(localized: "Next Page")
            buttons[forward.opposite]?.accessibilityLabel = String(localized: "Previous Page")
        }
    }

    /// One of the page's items: what it does when scrolled or activated.
    final class Element: UIAccessibilityElement {
        var scrolled: (UIAccessibilityScrollDirection) -> Bool = { _ in false }
        var activated: () -> Bool = { false }

        override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
            scrolled(direction)
        }

        override func accessibilityActivate() -> Bool {
            activated()
        }
    }
}
