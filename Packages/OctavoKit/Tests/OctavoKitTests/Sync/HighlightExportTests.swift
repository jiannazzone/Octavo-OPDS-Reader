import Foundation
import OctavoKit
import Testing

/// Share All Highlights' Markdown (#125).
struct HighlightExportTests {
    @Test func chaptersInOrderWithNotesUnderTheirQuotes() {
        let markdown = HighlightExport.markdown(
            title: "Pride and Prejudice", authors: ["Jane Austen"],
            highlights: [
                LocalHighlight(cfi: "a", text: "It is a truth universally acknowledged", note: "The opening", chapter: "Chapter 1"),
                LocalHighlight(cfi: "b", text: "single man", chapter: "Chapter 1"),
                LocalHighlight(cfi: "c", text: "Mr Collins", chapter: "Chapter 13"),
            ],
            notFound: [LocalHighlight(cfi: nil, text: "From another edition")],
            notFoundHeading: "Not Found in This File"
        )
        #expect(markdown == """
        # Pride and Prejudice

        Jane Austen

        ## Chapter 1

        > It is a truth universally acknowledged

        The opening

        > single man

        ## Chapter 13

        > Mr Collins

        ## Not Found in This File

        > From another edition

        """)
    }

    // Nothing in a quote or a note becomes a link, a heading or markup.
    @Test func quotesAndNotesAreTakenLiterally() {
        let markdown = HighlightExport.markdown(
            title: "T", authors: [],
            highlights: [LocalHighlight(cfi: "a", text: "[click](http://x) <b>", note: "# not a heading\n*two*")],
            notFound: [], notFoundHeading: ""
        )
        // An escaped bracket is no link.
        #expect(markdown.contains(#"> \[click\](http://x) \<b\>"#))
        #expect(markdown.contains(##"\# not a heading"##))
        #expect(markdown.contains(#"\*two\*"#))
    }

    // The text is shared as it is too, so ordinary punctuation stays.
    @Test func ordinaryPunctuationStaysReadable() {
        let markdown = HighlightExport.markdown(
            title: "T", authors: [],
            highlights: [LocalHighlight(cfi: "a", text: "Mr. Collins—well! (So it is.)", note: "1. First\n- dash")],
            notFound: [], notFoundHeading: ""
        )
        #expect(markdown.contains("> Mr. Collins—well! (So it is.)"))
        #expect(markdown.contains(#"1\. First"#))
        #expect(markdown.contains(#"\- dash"#))
    }

    @Test func theFileNameHoldsOnlyWhatAFileNameCan() {
        #expect(HighlightExport.fileName(title: "Pride and Prejudice", suffix: "Highlights") == "Pride and Prejudice – Highlights.md")
        #expect(HighlightExport.fileName(title: "AC/DC: Live?", suffix: "Highlights") == "AC-DC- Live- – Highlights.md")
        #expect(HighlightExport.fileName(title: "../..", suffix: "Highlights") == "- – Highlights.md")
        #expect(HighlightExport.fileName(title: "", suffix: "Highlights") == "Highlights.md")
    }
}
