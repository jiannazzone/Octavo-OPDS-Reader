import Foundation

/// How a book looks (decisions 13–16): the theme, font, text size, line
/// spacing and justification, set in the Text and theme panel and shared
/// by every book (decision 14). Kept in `UserDefaults` as one value.
nonisolated struct ReaderAppearance: Equatable, Sendable, Codable {
    var theme = ReaderTheme.original
    var font = ReaderFont.book
    /// A share of the book's own size; A− and A+ step through `textScales`.
    var textScale = 1.0
    /// Line height in lines, one of `lineSpacings`; `nil` keeps the book's own.
    var lineSpacing: Double?
    var justify = true
    /// Night while the iPhone is in Dark Mode, whatever the theme (decision
    /// 15). Off, the chosen theme stays.
    var matchDarkMode = true

    static let key = "reader.appearance"

    static let textScales = [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5, 1.75, 2.0]
    static let lineSpacings = [1.2, 1.35, 1.5, 1.65, 1.8]

    /// The theme on the page: Night in Dark Mode if it matches, else the
    /// chosen one.
    func theme(darkMode: Bool) -> ReaderTheme {
        matchDarkMode && darkMode ? .night : theme
    }

    var canShrinkText: Bool { textScale > Self.textScales[0] }
    var canGrowText: Bool { textScale < Self.textScales[Self.textScales.count - 1] }

    /// A− and A+: the next size down or up.
    mutating func stepText(by steps: Int) {
        let index = Self.textScales.lastIndex { $0 <= textScale } ?? 0
        textScale = Self.textScales[min(max(index + steps, 0), Self.textScales.count - 1)]
    }

    /// What the bridge applies after the book's own styles, and the page's
    /// colour around it.
    func script(darkMode: Bool) -> ReaderAppearanceScript {
        let theme = theme(darkMode: darkMode)
        var css: [String] = []
        if let colors = theme.colors {
            css.append("""
            html { background: \(colors.background) !important; color: \(colors.text) !important; }
            body, body * { color: \(colors.text) !important; background-color: transparent !important; }
            a:link, a:visited, a:link *, a:visited * { color: \(colors.link) !important; }
            """)
        }
        if textScale != 1 {
            css.append("html { font-size: \(Self.percent(textScale))% !important; }")
        }
        if let family = font.cssFamily {
            if !font.fontFaces.isEmpty { css.append(font.fontFaces) }
            css.append("body, body *:not(pre):not(code):not(kbd):not(samp) { font-family: \(family) !important; }")
        }
        // Element rules without `!important`: a book's own classes (verse,
        // a centred line) keep theirs.
        if let lineSpacing {
            css.append("p, li, blockquote, dd { line-height: \(lineSpacing); }")
        }
        css.append("p, li, blockquote, dd { text-align: \(justify ? "justify" : "start"); }")
        // Old books align with an attribute, which any style overrides.
        css.append("""
        [align="left"] { text-align: left; }
        [align="right"] { text-align: right; }
        [align="center"] { text-align: center; }
        [align="justify"] { text-align: justify; }
        """)
        return ReaderAppearanceScript(css: css.joined(separator: "\n"), background: theme.colors?.background ?? ReaderTheme.originalBackground)
    }

    private static func percent(_ scale: Double) -> String {
        (scale * 100).formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// The CSS and background colour the bridge's `setAppearance` takes.
nonisolated struct ReaderAppearanceScript: Equatable, Sendable {
    var css: String
    var background: String

    var scriptArguments: [String: Any] {
        ["css": css, "background": background]
    }
}

/// The four themes (decision 15). Original keeps the book's own colours on
/// white; the others set the page and text.
nonisolated enum ReaderTheme: String, CaseIterable, Sendable, Codable, Identifiable {
    case original, paper, sepia, night

    var id: Self { self }

    struct Colors: Equatable, Sendable {
        var background: String
        var text: String
        var link: String
    }

    static let originalBackground = "#ffffff"

    var name: String {
        switch self {
        case .original: "Original"
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .night: "Night"
        }
    }

    /// `nil`: the book's own colours on white.
    var colors: Colors? {
        switch self {
        case .original: nil
        case .paper: Colors(background: "#f7f3ea", text: "#2b2a28", link: "#5a4a2a")
        case .sepia: Colors(background: "#f3e9d2", text: "#3b2f1e", link: "#6b4a1e")
        case .night: Colors(background: "#121212", text: "#d6d3ce", link: "#9cb8e8")
        }
    }

    var isDark: Bool { self == .night }

    /// For the theme swatches.
    var background: String { colors?.background ?? Self.originalBackground }
    var text: String { colors?.text ?? "#000000" }
}

/// The fonts (decision 16): the book's own, the ones iOS ships, then the two
/// bundled in `ReaderWeb/fonts/`. The raw values are saved, so they stay.
nonisolated enum ReaderFont: String, CaseIterable, Sendable, Codable, Identifiable {
    case book, newYork, georgia, iowan, palatino, charter, sanSerif, atkinson, openDyslexic

    var id: Self { self }

    var name: String {
        switch self {
        case .book: "Book’s Font"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .iowan: "Iowan Old Style"
        case .palatino: "Palatino"
        case .charter: "Charter"
        case .sanSerif: "SF Pro"
        case .atkinson: "Atkinson Hyperlegible"
        case .openDyslexic: "OpenDyslexic"
        }
    }

    /// `nil`: the book's own. A bundled font goes by a name of ours, so a
    /// book's own `@font-face` is unlikely to share it.
    var cssFamily: String? {
        switch self {
        case .book: nil
        case .newYork: "ui-serif, serif"
        case .georgia: "Georgia, serif"
        case .iowan: "'Iowan Old Style', serif"
        case .palatino: "Palatino, 'Palatino Linotype', serif"
        case .charter: "Charter, serif"
        case .sanSerif: "-apple-system, system-ui, sans-serif"
        case .atkinson: "octavo-atkinson-hyperlegible-next, sans-serif"
        case .openDyslexic: "octavo-opendyslexic, sans-serif"
        }
    }

    /// The `@font-face` rules a bundled font needs, from the reader's own
    /// `fonts/` (the one place its CSP takes fonts from, besides the book's
    /// own); empty for the rest. Atkinson's files are variable, every weight.
    /// OpenDyslexic's "fi" and "ffi" ligatures leave a gap ("fi rst", "o ffice");
    /// the project's own later work drops them, so none are used here.
    var fontFaces: String {
        switch self {
        case .atkinson:
            [
                Self.fontFace("octavo-atkinson-hyperlegible-next", file: "AtkinsonHyperlegibleNext.woff2", weight: "200 800"),
                Self.fontFace("octavo-atkinson-hyperlegible-next", file: "AtkinsonHyperlegibleNext-Italic.woff2", weight: "200 800", italic: true),
            ].joined(separator: "\n")
        case .openDyslexic:
            [
                Self.fontFace("octavo-opendyslexic", file: "OpenDyslexic-Regular.woff2", weight: "400", ligatures: false),
                Self.fontFace("octavo-opendyslexic", file: "OpenDyslexic-Bold.woff2", weight: "700", ligatures: false),
                Self.fontFace("octavo-opendyslexic", file: "OpenDyslexic-Italic.woff2", weight: "400", italic: true, ligatures: false),
                Self.fontFace("octavo-opendyslexic", file: "OpenDyslexic-Bold-Italic.woff2", weight: "700", italic: true, ligatures: false),
            ].joined(separator: "\n")
        default: ""
        }
    }

    private static func fontFace(_ family: String, file: String, weight: String, italic: Bool = false, ligatures: Bool = true) -> String {
        "@font-face { font-family: \(family); src: url(\"\(ReaderSchemeHandler.fontsURL)\(file)\") format(\"woff2\"); font-weight: \(weight); font-style: \(italic ? "italic" : "normal");\(ligatures ? "" : " font-feature-settings: \"liga\" 0;") }"
    }
}

nonisolated extension ReaderAppearance {
    private enum CodingKeys: String, CodingKey {
        case theme, font, textScale, lineSpacing, justify, matchDarkMode
    }

    // Written out: as `RawRepresentable` (for `@AppStorage`) the type would
    // otherwise encode through `rawValue`, which encodes it again, forever.
    // Missing values (an older saved appearance) take the defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ReaderAppearance()
        theme = (try? container.decodeIfPresent(ReaderTheme.self, forKey: .theme)) ?? defaults.theme
        font = (try? container.decodeIfPresent(ReaderFont.self, forKey: .font)) ?? defaults.font
        textScale = (try? container.decodeIfPresent(Double.self, forKey: .textScale)) ?? defaults.textScale
        lineSpacing = try? container.decodeIfPresent(Double.self, forKey: .lineSpacing)
        justify = (try? container.decodeIfPresent(Bool.self, forKey: .justify)) ?? defaults.justify
        matchDarkMode = (try? container.decodeIfPresent(Bool.self, forKey: .matchDarkMode)) ?? defaults.matchDarkMode
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(font, forKey: .font)
        try container.encode(textScale, forKey: .textScale)
        try container.encodeIfPresent(lineSpacing, forKey: .lineSpacing)
        try container.encode(justify, forKey: .justify)
        try container.encode(matchDarkMode, forKey: .matchDarkMode)
    }
}

/// For `@AppStorage`. Being `RawRepresentable` also makes `==` compare
/// `rawValue`s (the standard library's, which wins over a synthesized one),
/// so the keys are sorted: the same appearance always encodes the same.
nonisolated extension ReaderAppearance: RawRepresentable {
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
