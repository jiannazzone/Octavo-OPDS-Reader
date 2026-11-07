import CoreText
import SwiftUI
import UIKit

/// A footnote where you are (decision 34): a glass card holding the whole note
/// in your font, size and theme, with Go to Note and ✕. Over the page, so the
/// sentence you're reading stays in view. It sits where `ReaderNotePlacement`
/// says, at the height the note wants.
struct ReaderNoteLayer: View {
    let note: ReaderNote
    let placement: ReaderNotePlacement
    let theme: ReaderTheme
    let goToNote: () -> Void
    let close: () -> Void
    /// A swipe on the card: it closes and turns, as one on the page does.
    let swiped: (ReaderTurnSide) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ReaderNoteLayout(placement: placement) {
            ReaderNoteCard(note: note, theme: theme, goToNote: goToNote, close: close, swiped: swiped)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// Asks the card how tall the note wants it, then places it.
private struct ReaderNoteLayout: Layout {
    let placement: ReaderNotePlacement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard let card = subviews.first else { return }
        let width = placement.span.upperBound - placement.span.lowerBound
        let wanted = card.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let frame = placement.frame(height: Double(wanted), textInset: ReaderNoteCard.textInset)
        card.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
    }
}

private struct ReaderNoteCard: View {
    let note: ReaderNote
    let theme: ReaderTheme
    let goToNote: () -> Void
    let close: () -> Void
    let swiped: (ReaderTurnSide) -> Void

    /// How far below the card's top its text starts: the buttons' row.
    static let textInset = 58.0
    private static let horizontalPadding = 18.0
    private static let cornerRadius = 26.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Go to Note", action: goToNote)
                    .font(.subheadline.weight(.semibold))
                    .padding(.leading, 4)
                Spacer()
                ReaderPanelCloseButton(close: close)
            }
            .padding([.horizontal, .top], 14)
            .frame(height: Self.textInset, alignment: .top)
            // The way out stays in place while a long note scrolls under it.
            ScrollView {
                ReaderNoteText(note: note, color: Color(hex: theme.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .glassEffect(.regular.tint(Color(hex: theme.background).opacity(0.72)), in: .rect(cornerRadius: Self.cornerRadius))
        .gesture(ReaderNoteCardSwipe(swiped: swiped))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// A sideways swipe on the card. UIKit's, as a SwiftUI drag anywhere on the card
/// keeps the page's own swipes (`ReaderSwipeRecognizer`) from starting.
private struct ReaderNoteCardSwipe: UIGestureRecognizerRepresentable {
    let swiped: (ReaderTurnSide) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        guard pan.state == .ended else { return }
        swiped(pan.translation(in: pan.view).x < 0 ? .right : .left)
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    /// Up and down is the note's own scrolling.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.5
        }
    }
}

/// The note's paragraphs.
private struct ReaderNoteText: View {
    let note: ReaderNote
    let color: Color

    var body: some View {
        let typeface = ReaderNoteTypeface(cssFamily: note.font.family, installed: ReaderFont.cardFamilies)
        let size = note.font.size
        VStack(alignment: .leading, spacing: size * 0.6) {
            ForEach(note.blocks.indices, id: \.self) { index in
                let block = note.blocks[index]
                Text(attributed(block, typeface: typeface, size: size))
                    .foregroundStyle(color)
                    .lineSpacing(lineSpacing(typeface: typeface, size: size))
                    .padding(.leading, Double(block.indent ?? 0) * size)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The page's lines' distance apart, where SwiftUI adds to the font's own.
    private func lineSpacing(typeface: ReaderNoteTypeface, size: Double) -> Double {
        guard let lineHeight = note.font.lineHeight else { return 0 }
        return max(0, lineHeight - Double(typeface.uiFont(size: size).lineHeight))
    }

    private func attributed(_ block: ReaderNote.Block, typeface: ReaderNoteTypeface, size: Double) -> AttributedString {
        block.runs.reduce(into: AttributedString()) { text, run in
            var part = AttributedString(run.text)
            let raised = run.sup == true || run.sub == true
            let face = run.code == true ? ReaderNoteTypeface.monospaced : typeface
            part.font = face.font(size: raised ? size * 0.72 : size, italic: run.italic == true, bold: run.bold == true)
            if run.sup == true { part.baselineOffset = size * 0.35 }
            if run.sub == true { part.baselineOffset = -size * 0.15 }
            text.append(part)
        }
    }
}

extension ReaderNoteTypeface {
    /// A fixed size, as the page's text is: Text and Theme sets it, not Dynamic
    /// Type.
    func font(size: Double, italic: Bool = false, bold: Bool = false) -> Font {
        var font: Font
        switch self {
        case .named(let family): font = .custom(family, fixedSize: size)
        // Its face picked by Core Text, with the page's ligatures setting.
        case .bundled(let bundled): return Font(bundled.cardFont(size: size, italic: italic, bold: bold))
        case .serif: font = .system(size: size, design: .serif)
        case .sansSerif: font = .system(size: size)
        case .monospaced: font = .system(size: size, design: .monospaced)
        }
        if italic { font = font.italic() }
        if bold { font = font.bold() }
        return font
    }

    func uiFont(size: Double) -> UIFont {
        let system = UIFont.systemFont(ofSize: size)
        return switch self {
        case .named(let family): UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: family]), size: size)
        case .bundled(let bundled): bundled.cardFont(size: size)
        case .serif: system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? system
        case .sansSerif: system
        case .monospaced: system.fontDescriptor.withDesign(.monospaced).map { UIFont(descriptor: $0, size: size) } ?? system
        }
    }
}

extension ReaderFont {
    /// The families the card can draw: the ones iOS has, and the bundled ones
    /// (#83), which SwiftUI can't see on the page. Those are registered with
    /// Core Text, for this run of the app, the first time a card asks: the same
    /// WOFF2 files the page loads, which Core Text reads as they are.
    static var cardFamilies: Set<String> {
        _ = registered
        return Set(UIFont.familyNames)
    }

    private static let registered: Void = {
        guard let fonts = Bundle.main.url(forResource: "ReaderWeb", withExtension: nil)?.appending(path: "fonts") else { return }
        for face in allCases.flatMap(\.bundledFaces) {
            CTFontManagerRegisterFontsForURL(fonts.appending(path: face.file) as CFURL, .process, nil)
        }
    }()

    /// A bundled font's face, as the page draws it: bold is Atkinson's 700
    /// instance or OpenDyslexic's bold file, and OpenDyslexic has no ligatures.
    /// The traits go in as attributes: `withSymbolicTraits` finds none of
    /// OpenDyslexic's faces, which carry another trait besides.
    func cardFont(size: Double, italic: Bool = false, bold: Bool = false) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if italic { traits.insert(.traitItalic) }
        if bold { traits.insert(.traitBold) }
        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: bundledFamily ?? "",
            .traits: [UIFontDescriptor.TraitKey.symbolic: traits.rawValue],
        ]
        if !usesLigatures {
            attributes[.featureSettings] = [[kCTFontOpenTypeFeatureTag: "liga", kCTFontOpenTypeFeatureValue: 0]]
        }
        return UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
    }
}
