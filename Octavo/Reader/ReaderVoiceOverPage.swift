import OctavoKit
import SwiftUI
import UIKit

/// The page as VoiceOver reads it, one item (#74, Adam 2026-11-14;
/// `docs/notes/accessibility.md`): the words on the page, from `bridge.js`,
/// in place of the book's own text, which runs on past the page and never
/// hears VoiceOver's page turns. A three-finger swipe turns the page, and at
/// the end of a page Read All turns it and reads on (`ReaderModel+VoiceOver`).
/// A double tap shows or hides the controls, as "…" does. Its words are
/// selectable text (#125): the Text Selection rotor picks words, lines or
/// sentences, the same words are selected in the book, and the highlight bar
/// comes up. Nothing to see or touch: taps reach the page under it.
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
        // Fixed-layout books have no highlights, and a page without words
        // nothing to select.
        view.setWords(model.isFixedLayout ? nil : model.pageWords)
        view.select = { [model] range, words in model.selectPageWords(range, in: words) }
        // The selection taken for a highlight, or gone with a tap: the words
        // let it go too.
        let selecting = model.selectionBox != nil
        if view.wasSelecting, !selecting { view.clearSelection() }
        view.wasSelecting = selecting
        // Each highlight on the page opens its card (#125), as a tap does.
        view.accessibilityCustomActions = model.highlightsOnPage.compactMap { onPage in
            guard let highlight = model.highlights.highlight(onPage.id) else { return nil }
            return UIAccessibilityCustomAction(name: Self.actionName(for: highlight.text)) { [model] _ in
                model.openHighlightCard(onPage.id)
                return true
            }
        }
    }

    /// "Highlight: “It is a truth universally…”", its first words.
    nonisolated static func actionName(for text: String) -> String {
        let words = text.split(separator: " ")
        let start = words.prefix(6).joined(separator: " ")
        let quote = words.count > 6 ? start + "…" : start
        return String(localized: "Highlight: “\(quote)”", comment: "VoiceOver: an action that opens a highlight on the page")
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

    final class PageView: UIView, UITextViewDelegate {
        var turn: (UIAccessibilityScrollDirection) -> Bool = { _ in false }
        var activate: () -> Void = {}
        /// The words selected, in them.
        var select: (NSRange, String) -> Void = { _, _ in }
        var wasSelecting = false
        /// The words as text VoiceOver can select in, through
        /// `accessibilityTextInputResponder`: hidden, so it's never drawn or
        /// read as an item of its own, and laid out over the page, so its
        /// rects are roughly where the words are.
        private let words = UITextView()
        /// A selection the words made themselves, not VoiceOver.
        private var isQuiet = false
        private var lastSelection = NSRange(location: 0, length: 0)

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = true
            accessibilityTraits = .causesPageTurn
            // Voice Control's name for it: its label is the whole page.
            accessibilityUserInputLabels = [String(localized: "Page")]
            words.isHidden = true
            words.isEditable = false
            words.isSelectable = true
            words.isScrollEnabled = false
            words.dataDetectorTypes = []
            words.font = .preferredFont(forTextStyle: .body)
            words.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            words.frame = bounds
            words.delegate = self
            addSubview(words)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// `nil`: nothing to select.
        func setWords(_ text: String?) {
            accessibilityTextInputResponder = text == nil ? nil : words
            guard words.text != (text ?? "") else { return }
            quietly { words.text = text ?? "" }
        }

        func clearSelection() {
            guard words.selectedRange.length > 0 else { return }
            quietly { words.selectedRange = NSRange(location: words.selectedRange.location, length: 0) }
        }

        private func quietly(_ change: () -> Void) {
            isQuiet = true
            change()
            isQuiet = false
            lastSelection = words.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            guard !isQuiet, range != lastSelection else { return }
            // A cursor moved with nothing selected before selects nothing.
            let wasEmpty = lastSelection.length == 0
            lastSelection = range
            if range.length == 0, wasEmpty { return }
            select(range, textView.text)
        }

        override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
            turn(direction)
        }

        override func accessibilityActivate() -> Bool {
            activate()
            return true
        }
    }
}
