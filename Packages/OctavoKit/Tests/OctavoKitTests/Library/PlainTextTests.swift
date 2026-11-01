import OctavoKit
import Testing

/// Descriptions carry markup the book controls, so they show as plain text
/// (`docs/notes/formats-spike.md`).
struct PlainTextTests {
    @Test func dropsInlineTags() {
        #expect(PlainText.fromHTML("Call me <i>Ishmael</i>. <b>Some</b> years ago") == "Call me Ishmael. Some years ago")
    }

    @Test func blocksBecomeParagraphs() {
        let html = "<p>First paragraph.</p>\n<p>Second\n  paragraph.</p>"
        #expect(PlainText.fromHTML(html) == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func lineBreaksStaySingle() {
        #expect(PlainText.fromHTML("One<br>Two<br/>Three") == "One\nTwo\nThree")
    }

    @Test func listItemsGetBullets() {
        #expect(PlainText.fromHTML("<p>Contents:</p><ul><li>One</li><li>Two</li></ul>") == "Contents:\n\n• One\n• Two")
    }

    @Test func scriptsAndStylesAreNotText() {
        let html = "<style>p { color: red }</style><p>Text</p><script>alert(1)</script><SCRIPT>x()</SCRIPT>"
        #expect(PlainText.fromHTML(html) == "Text")
    }

    // FB2 descriptions keep links with javascript: targets (formats-spike).
    @Test func linksKeepOnlyTheirText() {
        #expect(PlainText.fromHTML(#"See <a href="javascript:alert(1)">this</a>."#) == "See this.")
    }

    @Test func commentsVanish() {
        #expect(PlainText.fromHTML("A<!-- <p>hidden</p> -->B") == "AB")
    }

    @Test func decodesEntities() {
        #expect(PlainText.fromHTML("<p>Fish &amp; chips &mdash; &#233;t&#xE9; &lt;3</p>") == "Fish & chips — été <3")
    }

    // Escaped markup is text, and stays text.
    @Test func escapedTagsStayText() {
        #expect(PlainText.fromHTML("<p>&lt;b&gt;not bold&lt;/b&gt;</p>") == "<b>not bold</b>")
    }

    @Test func unknownEntitiesStayAsWritten() {
        #expect(PlainText.fromHTML("<p>AT&T &bogus; &#xZZ;</p>") == "AT&T &bogus; &#xZZ;")
    }

    @Test func invalidCodePointsBecomeReplacement() {
        #expect(PlainText.fromHTML("<p>a&#0;b&#xD800;c</p>") == "a\u{FFFD}b\u{FFFD}c")
    }

    @Test func aLoneLessThanIsText() {
        #expect(PlainText.fromHTML("<p>1 < 2 and 3 > 2</p>") == "1 < 2 and 3 > 2")
    }

    @Test func plainTextKeepsItsLineBreaks() {
        #expect(PlainText.fromHTML("First line.\r\n\r\nSecond, 2 < 3 &amp; more.\n") == "First line.\n\nSecond, 2 < 3 & more.")
    }

    @Test func emptyMarkupIsEmpty() {
        #expect(PlainText.fromHTML("<p> </p><div><br></div>") == "")
    }

    @Test func unclosedTagKeepsTheRest() {
        #expect(PlainText.fromHTML("<p>Text <b") == "Text <b")
    }
}
