import Foundation
import Testing
@testable import Octavo

/// How a book looks (decisions 13–16): the theme on the page, the size and
/// spacing steps, the CSS the bridge applies, and the saved value.
struct ReaderAppearanceTests {
    // MARK: Theme

    @Test func darkModeMeansNightWhileItMatches() {
        var appearance = ReaderAppearance(theme: .sepia)
        #expect(appearance.theme(darkMode: false) == .sepia)
        #expect(appearance.theme(darkMode: true) == .night)
        appearance.matchDarkMode = false
        #expect(appearance.theme(darkMode: true) == .sepia)
    }

    // MARK: Steps

    @Test func textSizeStepsStopAtEachEnd() {
        var appearance = ReaderAppearance()
        appearance.stepText(by: 1)
        #expect(appearance.textScale == 1.1)
        appearance.stepText(by: -2)
        #expect(appearance.textScale == 0.9)
        appearance.stepText(by: -10)
        #expect(appearance.textScale == ReaderAppearance.textScales.first)
        #expect(!appearance.canShrinkText)
        appearance.stepText(by: 100)
        #expect(appearance.textScale == ReaderAppearance.textScales.last)
        #expect(!appearance.canGrowText)
    }

    // The menu's first choice: nothing of a chosen spacing stays, on the page
    // or saved.
    @Test func lineSpacingGoesBackToTheBooks() throws {
        var appearance = ReaderAppearance(lineSpacing: 1.65)
        #expect(appearance.script(darkMode: false).css.contains("line-height: 1.65;"))

        appearance.lineSpacing = nil
        #expect(!appearance.script(darkMode: false).css.contains("line-height"))
        let saved = try #require(ReaderAppearance(rawValue: appearance.rawValue))
        #expect(saved.lineSpacing == nil)
    }

    // MARK: CSS

    @Test func theDefaultsKeepTheBooksLookButJustify() {
        let script = ReaderAppearance().script(darkMode: false)
        #expect(script.background == ReaderTheme.originalBackground)
        #expect(!script.css.contains("color:"))
        #expect(!script.css.contains("font-size"))
        #expect(!script.css.contains("font-family"))
        #expect(!script.css.contains("line-height"))
        #expect(script.css.contains("text-align: justify"))
    }

    // `html` takes the page colour; were it cleared with the rest, the book's
    // frame would show white under Night.
    @Test func aThemeColoursThePageAndClearsTheBooksBackgrounds() {
        let script = ReaderAppearance(theme: .paper).script(darkMode: true)
        let night = try! #require(ReaderTheme.night.colors)
        #expect(script.background == night.background)
        #expect(script.css.contains("html { background: \(night.background) !important;"))
        #expect(script.css.contains("body, body * {"))
        #expect(!script.css.contains("html, body"))
    }

    @Test func sizeFontSpacingAndAlignmentBecomeRules() {
        let appearance = ReaderAppearance(font: .georgia, textScale: 1.35, lineSpacing: 1.5, justify: false)
        let css = appearance.script(darkMode: false).css
        #expect(css.contains("html { font-size: 135% !important; }"))
        #expect(css.contains("font-family: Georgia, serif !important"))
        #expect(css.contains(":not(pre)"))
        #expect(css.contains("line-height: 1.5;"))
        #expect(css.contains("text-align: start"))
        #expect(css.contains("[align=\"center\"] { text-align: center; }"))
    }

    // MARK: Saved value

    // `@AppStorage` keeps it as `rawValue`; encoding once recursed through
    // `RawRepresentable` until the stack ran out. `==` compares `rawValue`s
    // too, so equal values must encode alike.
    @Test func theSavedValueRoundTrips() {
        let appearance = ReaderAppearance(theme: .night, font: .charter, textScale: 0.9, lineSpacing: 1.8, justify: false, matchDarkMode: false)
        #expect(ReaderAppearance(rawValue: appearance.rawValue) == appearance)
        #expect(ReaderAppearance(rawValue: ReaderAppearance().rawValue) == ReaderAppearance())
    }

    @Test func missingOrUnknownValuesTakeTheDefaults() {
        #expect(ReaderAppearance(rawValue: "{}") == ReaderAppearance())
        let partial = ReaderAppearance(rawValue: #"{"theme":"sepia","font":"comicSans"}"#)
        #expect(partial == ReaderAppearance(theme: .sepia))
        #expect(ReaderAppearance(rawValue: "not json") == nil)
    }
}
