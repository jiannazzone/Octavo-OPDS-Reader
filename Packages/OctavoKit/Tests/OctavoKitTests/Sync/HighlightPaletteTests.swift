import OctavoKit
import Testing

/// How a stored highlight colour is drawn (#125).
struct HighlightPaletteTests {
    @Test func bookOrbitsTenAreKnownByHexOrName() {
        #expect(HighlightPalette.colors.count == 10)
        #expect(HighlightPalette.color(for: "#facc15")?.name == "yellow")
        #expect(HighlightPalette.color(for: "Green")?.hex == "#4ADE80")
        #expect(HighlightPalette.color(for: "grey")?.hex == "#9CA3AF")
        #expect(HighlightPalette.color(for: "#FF8800") == nil)
    }

    // A name means BookOrbit's colour, not CSS's.
    @Test func aNameIsDrawnAsBookOrbitsColour() {
        #expect(HighlightPalette.drawable("yellow") == "#FACC15")
    }

    // KOReader's own colours, say.
    @Test func anyOtherHexIsDrawnAsItIs() {
        #expect(HighlightPalette.drawable("#ff8800") == "#FF8800")
        #expect(HighlightPalette.drawable("#ff880080") == "#FF880080")
        #expect(HighlightPalette.drawable("#f80") == "#FF8800")
    }

    // Nothing but a hex ever reaches the page.
    @Test func anythingElseIsDrawnYellow() {
        #expect(HighlightPalette.drawable("lightblue") == "#FACC15")
        #expect(HighlightPalette.drawable("#12345") == "#FACC15")
        #expect(HighlightPalette.drawable("red\" onload=\"x") == "#FACC15")
        #expect(HighlightPalette.drawable("#gggggg") == "#FACC15")
        #expect(HighlightPalette.drawable("") == "#FACC15")
    }
}
