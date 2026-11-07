import CoreGraphics
import Foundation

/// A footnote, as the bridge read it from the book (decision 34,
/// `docs/notes/footnotes.md`): its words and which are italic and such, never
/// its markup, so nothing of the book's runs in the card.
nonisolated struct ReaderNote: Codable, Equatable, Sendable {
    nonisolated struct Run: Codable, Equatable, Sendable {
        var text: String
        var italic: Bool?
        var bold: Bool?
        var sup: Bool?
        var sub: Bool?
        var code: Bool?
    }

    /// A paragraph, or a line of verse with its line breaks in its text.
    nonisolated struct Block: Codable, Equatable, Sendable {
        var runs: [Run]
        /// How many quotes it's inside.
        var indent: Int?
    }

    /// The mark in the page's coordinates, which are the screen's.
    nonisolated struct Mark: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// The text around the mark, as WebKit worked it out: the book's own, or
    /// what's set in Text and Theme.
    nonisolated struct Font: Codable, Equatable, Sendable {
        /// A CSS `font-family`.
        var family: String?
        var size: Double
        var lineHeight: Double?
    }

    /// Where the note sits in the book, for Go to Note.
    var href: String
    var mark: Mark
    var font: Font
    var blocks: [Block]
}

/// Where a note's card goes (decision 34). On a spread, on the other page from
/// its mark, level with it. On one page, along the bottom above the footer, or
/// at the top if the mark is down there. A long note grows to the height of the
/// page, and then scrolls.
nonisolated struct ReaderNotePlacement: Equatable, Sendable {
    /// The card's left and right edges.
    var span: ClosedRange<Double>
    /// How far up and down it can go.
    var top: Double
    var bottom: Double
    var markTop: Double
    var markBottom: Double
    /// On the other page from the mark.
    var isFacing: Bool

    /// How far the card keeps from the footer's line, and from the mark's on
    /// one page.
    static let clearance = 4.0

    init(mark: ReaderNote.Mark, layout: ReaderLayout, geometry: ReaderGeometry) {
        let spans = layout.barSpans(in: geometry, bookMode: true)
        if spans.count == 2, let fold = layout.fold {
            isFacing = true
            span = mark.x + mark.width / 2 < (fold.lowerBound + fold.upperBound) / 2 ? spans[1] : spans[0]
        } else {
            isFacing = false
            span = spans[0]
        }
        top = geometry.safeArea.top + ReaderLayout.edgeInset
        bottom = ReaderChromeLayout.footerLineTop(in: geometry, layout: layout) - Self.clearance
        markTop = mark.y
        markBottom = mark.y + mark.height
    }

    /// The card's frame for a note wanting `height`. `textInset`: how far below
    /// the card's top its text starts, to bring the text level with the mark.
    func frame(height: Double, textInset: Double) -> CGRect {
        let height = min(height, bottom - top)
        return CGRect(x: span.lowerBound, y: y(height: height, textInset: textInset), width: span.upperBound - span.lowerBound, height: height)
    }

    private func y(height: Double, textInset: Double) -> Double {
        let alongBottom = bottom - height
        if isFacing { return max(top, min(markTop - textInset, alongBottom)) }
        if alongBottom >= markBottom + Self.clearance { return alongBottom }
        if top + height <= markTop - Self.clearance { return top }
        // Too long to miss it.
        return markTop > (top + bottom) / 2 ? top : alongBottom
    }
}

/// The reader's font as the card can draw it. A CSS family, reduced to one iOS
/// has: a book's own embedded font isn't known outside the page, so that comes
/// out as the family it falls back to. Our bundled fonts are registered for the
/// card (`ReaderFont.cardFamily(named:)`), and come out as themselves.
nonisolated enum ReaderNoteTypeface: Equatable, Sendable {
    case named(String)
    /// One of `ReaderFont`'s bundled fonts, drawn from the same files as on the
    /// page.
    case bundled(ReaderFont)
    case serif
    case sansSerif
    case monospaced

    /// WebKit's own font for a book that sets none.
    static let standard = ReaderNoteTypeface.named("Times New Roman")

    /// `installed`: the families iOS has.
    init(cssFamily: String?, installed: Set<String>) {
        let installed = Dictionary(installed.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        self.init(cssFamily: cssFamily) { installed[$0.lowercased()] }
    }

    /// `family`: the family iOS has by that name, as iOS spells it, or `nil`.
    init(cssFamily: String?, family: (String) -> String?) {
        let names = (cssFamily ?? "").split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespacesAndNewlines))
        }
        for name in names {
            switch name.lowercased() {
            case "ui-serif": self = .serif
            case "-apple-system", "system-ui", "ui-sans-serif", "blinkmacsystemfont": self = .sansSerif
            case "ui-monospace": self = .monospaced
            case "serif", "times", "-webkit-standard": self = .standard
            case "sans-serif": self = .named("Helvetica")
            case "monospace": self = .named("Courier")
            case let lowered:
                if let bundled = ReaderFont.allCases.first(where: { $0.bundledName == lowered }) {
                    // Not registered: the page's next one, as for a book's own.
                    guard let name = bundled.bundledFamily, family(name) != nil else { continue }
                    self = .bundled(bundled)
                } else {
                    guard let found = family(name) else { continue }
                    self = .named(found)
                }
            }
            return
        }
        self = .standard
    }
}
