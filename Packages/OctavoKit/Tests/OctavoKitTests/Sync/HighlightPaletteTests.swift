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

/// A highlight's range as a point, for going to it (#125).
struct ReaderCFITests {
    @Test func aRangeStartsAtItsParentAndStart() {
        #expect(ReaderCFI.start(of: "epubcfi(/6/4!/4/38/2,/1:143,/1:150)") == "epubcfi(/6/4!/4/38/2/1:143)")
    }

    @Test func aPointStaysAsItIs() {
        #expect(ReaderCFI.start(of: "epubcfi(/6/4!/4/38/2/1:143)") == "epubcfi(/6/4!/4/38/2/1:143)")
    }

    @Test func rangesOrderAsTheBookReads() {
        let ineffable = "epubcfi(/6/4!/4/38/2,/1:116,/1:125)"
        let collins = "epubcfi(/6/4!/4/38/2,/1:143,/1:150)"
        let nextParagraph = "epubcfi(/6/4!/4/38/4,/1:17,/1:25)"
        let nextChapter = "epubcfi(/6/6!/4/2,/1:0,/1:5)"
        #expect(ReaderCFI.starts(ineffable, before: collins))
        #expect(!ReaderCFI.starts(collins, before: ineffable))
        #expect(ReaderCFI.starts(collins, before: nextParagraph))
        #expect(ReaderCFI.starts(nextParagraph, before: nextChapter))
        // 10 comes after 9, as numbers.
        #expect(ReaderCFI.starts("epubcfi(/6/4!/4/9,/1:0,/1:1)", before: "epubcfi(/6/4!/4/10,/1:0,/1:1)"))
        #expect(ReaderCFI.starts("epubcfi(/6/4!/4[x10]/2,/1:0,/1:1)", before: "epubcfi(/6/4!/4[a]/4,/1:0,/1:1)"))
    }

    @Test func anEscapedCommaIsntASeparator() {
        #expect(ReaderCFI.start(of: "epubcfi(/6/4!/4[a^,b]/2,/1:0,/1:5)") == "epubcfi(/6/4!/4[a^,b]/2/1:0)")
    }
}
