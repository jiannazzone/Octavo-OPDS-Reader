import Foundation
import Testing
import WebKit
@testable import Octavo

/// Where a note's card goes, and the message that brings one (decision 34).
struct ReaderNotePlacementTests {
    /// As measured on the Duo: text 139–448 | 503–812 unfolded, 27–355 folded.
    private static let unfolded = ReaderGeometry(
        size: CGSize(width: 951, height: 669),
        divisions: [.init(frame: CGRect(x: 455.5, y: 0, width: 40, height: 669), isActive: false)],
        safeArea: ReaderInsets(top: 0, left: 0, bottom: 34, right: 84)
    )
    private static let folded = ReaderGeometry(
        size: CGSize(width: 466, height: 678),
        safeArea: ReaderInsets(top: 0, left: 0, bottom: 34, right: 84)
    )

    private static func mark(x: Double, y: Double) -> ReaderNote.Mark {
        ReaderNote.Mark(x: x, y: y, width: 8, height: 12)
    }

    private func spread() -> ReaderLayout {
        ReaderLayout(posture: .open, geometry: Self.unfolded, margins: .medium)
    }

    private func onePage() -> ReaderLayout {
        ReaderLayout(posture: .closed, geometry: Self.folded, margins: .medium)
    }

    @Test func aMarkOnTheLeftPageOpensOnTheRight() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 300, y: 200), layout: spread(), geometry: Self.unfolded)
        #expect(placement.isFacing)
        #expect(placement.span.lowerBound > 495.5)
        #expect(placement.span.upperBound <= 951 - 84)
    }

    @Test func aMarkOnTheRightPageOpensOnTheLeftAsWideAndClearOfTheFold() {
        let right = ReaderNotePlacement(mark: Self.mark(x: 300, y: 200), layout: spread(), geometry: Self.unfolded)
        let left = ReaderNotePlacement(mark: Self.mark(x: 600, y: 200), layout: spread(), geometry: Self.unfolded)
        #expect(left.span.upperBound < 455.5)
        #expect(left.span.upperBound - left.span.lowerBound == right.span.upperBound - right.span.lowerBound)
    }

    @Test func onTheFacingPageTheTextIsLevelWithTheMark() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 300, y: 200), layout: spread(), geometry: Self.unfolded)
        let frame = placement.frame(height: 150, textInset: 58)
        #expect(Double(frame.minY) == 200 - 58)
        #expect(Double(frame.height) == 150)
    }

    @Test func aMarkLowDownMovesTheCardUpToFit() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 300, y: 560), layout: spread(), geometry: Self.unfolded)
        let frame = placement.frame(height: 300, textInset: 58)
        #expect(Double(frame.maxY) == placement.bottom)
    }

    @Test func aMarkAtTheTopKeepsTheCardOnThePage() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 300, y: 20), layout: spread(), geometry: Self.unfolded)
        #expect(Double(placement.frame(height: 150, textInset: 58).minY) == placement.top)
    }

    @Test func aLongNoteGrowsToTheHeightOfThePageThenScrolls() {
        for (layout, geometry) in [(spread(), Self.unfolded), (onePage(), Self.folded)] {
            let placement = ReaderNotePlacement(mark: Self.mark(x: 300, y: 300), layout: layout, geometry: geometry)
            let frame = placement.frame(height: 5000, textInset: 58)
            #expect(Double(frame.minY) == placement.top)
            #expect(Double(frame.maxY) == placement.bottom)
        }
    }

    @Test func itStopsAboveTheFooter() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 100, y: 100), layout: onePage(), geometry: Self.folded)
        let footerCentre = 678 - onePage().bottomInset - ReaderLayout.verticalMargin / 2
        #expect(placement.bottom <= footerCentre - 10)
    }

    @Test func onOnePageItGoesAlongTheBottom() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 100, y: 100), layout: onePage(), geometry: Self.folded)
        #expect(!placement.isFacing)
        #expect(Double(placement.frame(height: 150, textInset: 58).maxY) == placement.bottom)
    }

    @Test func onOnePageAMarkDownThereSendsItToTheTop() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 100, y: 540), layout: onePage(), geometry: Self.folded)
        #expect(Double(placement.frame(height: 150, textInset: 58).minY) == placement.top)
    }

    @Test func onOnePageATallNoteMissesTheMarkIfItCan() {
        let placement = ReaderNotePlacement(mark: Self.mark(x: 100, y: 320), layout: onePage(), geometry: Self.folded)
        // Too tall for the room below the mark, which the room above still has.
        let frame = placement.frame(height: 285, textInset: 58)
        #expect(Double(frame.minY) == placement.top)
        #expect(Double(frame.maxY) < 320)
    }

    @Test func aReportedHalfOpenSpreadIsLaidOutTheSame() {
        let flat = ReaderNotePlacement(mark: Self.mark(x: 300, y: 200), layout: spread(), geometry: Self.unfolded)
        let halfOpen = ReaderNotePlacement(
            mark: Self.mark(x: 300, y: 200),
            layout: ReaderLayout(posture: .halfOpen, geometry: Self.unfolded, margins: .medium),
            geometry: Self.unfolded
        )
        #expect(flat == halfOpen)
    }
}

struct ReaderNoteTypefaceTests {
    private let installed: Set<String> = ["Georgia", "Times New Roman", "Iowan Old Style", "Palatino", "Charter"]

    @Test func usesTheFirstFamilyIOSHas() {
        #expect(ReaderNoteTypeface(cssFamily: "Georgia, serif", installed: installed) == .named("Georgia"))
        #expect(ReaderNoteTypeface(cssFamily: "\"Iowan Old Style\", serif", installed: installed) == .named("Iowan Old Style"))
        #expect(ReaderNoteTypeface(cssFamily: "palatino, 'Palatino Linotype', serif", installed: installed) == .named("Palatino"))
    }

    @Test func aBooksEmbeddedFontFallsBackToWhatItNames() {
        #expect(ReaderNoteTypeface(cssFamily: "\"Crimson Text\", Georgia, serif", installed: installed) == .named("Georgia"))
        #expect(ReaderNoteTypeface(cssFamily: "\"Crimson Text\"", installed: installed) == .standard)
    }

    @Test func genericsAreWhatWebKitDrawsThemAs() {
        #expect(ReaderNoteTypeface(cssFamily: "ui-serif, serif", installed: installed) == .serif)
        #expect(ReaderNoteTypeface(cssFamily: "-apple-system, system-ui, sans-serif", installed: installed) == .sansSerif)
        #expect(ReaderNoteTypeface(cssFamily: "serif", installed: installed) == .standard)
        #expect(ReaderNoteTypeface(cssFamily: "Times", installed: installed) == .standard)
        #expect(ReaderNoteTypeface(cssFamily: nil, installed: installed) == .standard)
    }
}

/// Which links are notes and what the card gets, through the real bridge and
/// foliate in a page that's never shown. Each kind of link is one a real book
/// uses, or one that a wrong guess would stop working as a link.
@MainActor
@Suite(.temporaryFiles, .serialized, .timeLimit(.minutes(1)))
struct ReaderNotesBridgeTests {
    private struct Link: Decodable {
        var text: String
        var href: String
        var note: [ReaderNote.Block]?

        var words: String? {
            note?.map { $0.runs.map(\.text).joined() }.joined(separator: " | ")
        }
    }

    private static let filler = String(repeating: "Some running words around it all. ", count: 4)

    private static let chapter = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>One</title></head><body>
    <h2 id="start">Chapter One</h2>
    <p>Standard Ebooks marks its notes.<a href="notes.xhtml#note-1" id="noteref-1" role="doc-noteref" epub:type="noteref">1</a> And one in verse.<a href="notes.xhtml#note-2" id="noteref-2" role="doc-noteref" epub:type="noteref">2</a> And quoted.<a href="notes.xhtml#note-9" id="noteref-9" role="doc-noteref" epub:type="noteref">9</a></p>
    <p>Project Gutenberg doesn't.<a class="fnanchor" href="#Footnote_A_1" id="FNanchor_A_1">[A]</a> \#(filler)</p>
    <div class="footnotes"><h3>FOOTNOTES:</h3>
    <div class="footnote"><p><a href="#FNanchor_A_1" id="Footnote_A_1"><span class="label">[A]</span></a> First paragraph, <i>italic</i>.</p><p>Second paragraph.</p></div>
    </div>
    <p>A modern book raises them<sup><a href="notes.xhtml#n3" id="r3">3</a></sup> or puts the link outside<a href="notes.xhtml#n4" id="r4"><sup>4</sup></a> or points at an empty anchor<a href="notes.xhtml#n5">*</a> or a note with a number that links back<a href="notes.xhtml#n6" id="r6">(6)</a>.</p>
    <p>A marked note with a picture<a epub:type="noteref" href="notes.xhtml#pic">7</a> or a table<a epub:type="noteref" href="notes.xhtml#table">8</a> is a jump. A note that tries to run a script<a epub:type="noteref" href="notes.xhtml#script">10</a> is only words.</p>
    <div id="wrapper"><p>Inside a box with an id<a epub:type="noteref" href="notes.xhtml#wrapped">11</a>, a stanza break<a epub:type="noteref" href="notes.xhtml#stanza">12</a>, preformatted verse<a epub:type="noteref" href="notes.xhtml#pre">13</a>, a picture in a link<a epub:type="noteref" href="notes.xhtml#icon">14</a>, a picture as the way back<a epub:type="noteref" id="r15" href="notes.xhtml#iconback">15</a>, too many paragraphs<a epub:type="noteref" href="notes.xhtml#many">16</a>, too long<a epub:type="noteref" href="notes.xhtml#long">17</a>, too deep<a epub:type="noteref" href="notes.xhtml#deep">18</a>.</p></div>
    <p>See the <a href="two.xhtml">next chapter</a>, or <a href="two.xhtml#start">Chapter 2</a>, or chapter <a href="two.xhtml#start">2</a>, or the words <a href="two.xhtml#para">here</a>, or the middle of a paragraph <a href="two.xhtml#middle">5</a>, or page <a href="two.xhtml#pg12">12</a>, or the web at <a href="https://example.com/#a">1</a>, or a link with nowhere to go <a href="two.xhtml#missing">3</a>.</p>
    <p><a href="#start">1</a> <a href="#start">2</a> <a href="#start">3</a></p>
    <ol><li><a href="two.xhtml#para">4</a></li></ol>
    </body></html>
    """#

    private static let notes = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Notes</title></head><body>
    <section id="endnotes" role="doc-endnotes" epub:type="endnotes footnotes"><h2>Endnotes</h2><ol>
    <li id="note-1" epub:type="endnote footnote"><p>The <i>first</i> note.<sup>a</sup> <a href="one.xhtml#noteref-1" role="doc-backlink" epub:type="backlink">↩︎</a></p><p>Its second
       paragraph.</p></li>
    <li id="note-2" epub:type="endnote footnote"><blockquote><p><span>One line,</span><br/><span>and another.</span></p></blockquote><p><a href="one.xhtml#noteref-2" role="doc-backlink" epub:type="backlink">↩︎</a></p></li>
    <li id="note-9" epub:type="endnote"><blockquote><p>Quoted.</p></blockquote><p>See <a href="two.xhtml#para">the page</a>. <a href="one.xhtml#noteref-9">↩</a></p></li>
    <li id="pic" epub:type="endnote"><p>A picture: <img src="x.png" alt="x"/></p></li>
    <li id="table" epub:type="endnote"><table><tr><td>A table</td></tr></table></li>
    <li id="script" epub:type="endnote"><p onclick="alert(1)">Words.<script>document.documentElement.setAttribute('data-ran', 'note')</script></p></li>
    <li id="wrapped" epub:type="endnote"><p>See <a href="one.xhtml#wrapper">the whole of that box</a>. <a href="one.xhtml#wrapper">↩</a></p></li>
    <li id="stanza" epub:type="endnote"><p>One.<br/><br/>Two.</p></li>
    <li id="pre" epub:type="endnote"><pre>  Indented,
    and more.</pre></li>
    <li id="icon" epub:type="endnote"><p>Words. <a href="two.xhtml"><img src="x.png" alt=""/></a></p></li>
    <li id="iconback" epub:type="endnote"><p>Words. <a href="one.xhtml#r15"><img src="x.png" alt=""/></a></p></li>
    <li id="many" epub:type="endnote">\#(String(repeating: "<p>x</p>", count: 201))</li>
    <li id="long" epub:type="endnote"><p>\#(String(repeating: "word ", count: 4001))</p></li>
    <li id="deep" epub:type="endnote">\#(String(repeating: "<blockquote>", count: 6))<p>Deep.</p>\#(String(repeating: "</blockquote>", count: 6))</li>
    </ol></section>
    <p id="n3"><a href="one.xhtml#r3">3.</a> A raised note.</p>
    <p id="n4">4. A note that keeps its own number.</p>
    <a id="n5"></a><p>A note after an empty anchor.</p>
    <p id="n6"><a href="one.xhtml#elsewhere">(6)</a> A number that links back somewhere else.</p>
    </body></html>
    """#

    private static let two = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Two</title></head><body>
    <section id="start"><h2>Chapter Two</h2><p id="para">A paragraph with <a id="middle"></a>an anchor in it.</p></section>
    <p><span id="pg12" epub:type="pagebreak"></span>A new page's words.</p>
    </body></html>
    """#

    private static let book: Data = {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:uuid:7b0c5b2e-0000-4000-8000-000000000034</dc:identifier>
        <dc:title>Notes</dc:title>
        <meta property="dcterms:modified">2026-11-05T00:00:00Z</meta>
        </metadata>
        <manifest>
        <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
        <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
        <item id="notes" href="notes.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine><itemref idref="one"/><itemref idref="two"/><itemref idref="notes"/></spine>
        </package>
        """
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        return StoredZip.make([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/one.xhtml", Data(chapter.utf8)),
            ("OEBPS/two.xhtml", Data(two.utf8)),
            ("OEBPS/notes.xhtml", Data(notes.utf8)),
        ])
    }()

    private func opened() async throws -> ReaderModel {
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "notes.epub")
        try Self.book.write(to: url)
        let store = ReadingPositionStore(directory: directory.appending(path: "positions", directoryHint: .isDirectory))
        let book = ReaderBook(fileURL: url, id: "notes")
        let model = ReaderModel(book: book, store: store, bookmarks: ReaderBookmarks(bookID: book.id, store: BookmarkStore(directory: directory.appending(path: "bookmarks", directoryHint: .isDirectory))))
        let opened = await eventually(timeout: .seconds(30)) { model.phase != .loading && model.relocation != nil }
        #expect(opened, "\(model.phase) \(model.lastError ?? "")")
        // The page isn't on screen, so it draws no frames; these don't wait for one.
        _ = try await model.page.callJavaScript("window.requestAnimationFrame = f => setTimeout(f, 16)")
        return model
    }

    private func links(_ model: ReaderModel) async throws -> [Link] {
        let json = try #require(try await model.page.callJavaScript("return await window.octavo.noteLinks()") as? String)
        return try JSONDecoder().decode([Link].self, from: Data(json.utf8))
    }

    @Test func eachLinkOpensWhatItShould() async throws {
        let model = try await opened()
        let links = try await links(model)
        func note(_ href: String) -> Link? { links.first { $0.href == href } }

        // Marked, whatever the note holds as long as the card can draw it.
        #expect(note("notes.xhtml#note-1")?.words == "The first note.a | Its second paragraph.")
        #expect(note("notes.xhtml#note-2")?.words == "One line,\nand another.")
        #expect(note("notes.xhtml#note-9")?.words == "Quoted. | See the page.")
        // Unmarked, in a box of its own, and its number that links back goes.
        #expect(note("#Footnote_A_1")?.words == "First paragraph, italic. | Second paragraph.")
        // Modern books' raised numbers.
        #expect(note("notes.xhtml#n3")?.words == "A raised note.")
        #expect(note("notes.xhtml#n4")?.words == "4. A note that keeps its own number.")
        #expect(note("notes.xhtml#n5")?.words == "A note after an empty anchor.")
        #expect(note("notes.xhtml#n6")?.words == "A number that links back somewhere else.")
        // Words only: a script's text isn't among them.
        #expect(note("notes.xhtml#script")?.words == "Words.")

        // A link's words stay, though it goes to a box around the mark.
        #expect(note("notes.xhtml#wrapped")?.words == "See the whole of that box.")
        #expect(note("notes.xhtml#stanza")?.words == "One.\n\nTwo.")
        #expect(note("notes.xhtml#pre")?.words == "  Indented,\nand more.")
        #expect(note("notes.xhtml#iconback")?.words == "Words.")
        #expect(note("notes.xhtml#deep")?.note?[0].indent == 4)

        // Only the page can draw these, so they're jumps.
        #expect(note("notes.xhtml#pic")?.note == nil)
        #expect(note("notes.xhtml#table")?.note == nil)
        #expect(note("notes.xhtml#icon")?.note == nil)
        // More than a note could be.
        #expect(note("notes.xhtml#many")?.note == nil)
        #expect(note("notes.xhtml#long")?.note == nil)

        // Links that have to keep working as links.
        let jumps = ["two.xhtml", "two.xhtml#start", "two.xhtml#para", "two.xhtml#middle", "two.xhtml#pg12", "two.xhtml#missing", "https://example.com/#a", "#start"]
        for link in links where jumps.contains(link.href) {
            #expect(link.note == nil, "\(link.text) → \(link.href)")
        }
        // A note's own way back, marked and not.
        #expect(note("#FNanchor_A_1")?.note == nil)
        #expect(note("one.xhtml#noteref-1")?.note == nil)
        #expect(note("one.xhtml#r3")?.note == nil)

        // The styles and quotes come through.
        let first = try #require(note("notes.xhtml#note-1")?.note)
        #expect(first[0].runs.map(\.text) == ["The ", "first", " note.", "a"])
        #expect(first[0].runs[1].italic == true)
        #expect(first[0].runs[3].sup == true)
        #expect(note("notes.xhtml#note-2")?.note?[0].indent == 1)

        // Nothing in a note runs.
        let ran = try await model.page.callJavaScript("return document.documentElement.getAttribute('data-ran')")
        #expect(ran is NSNull || ran == nil)
    }

    @Test func aNoteMessageDecodes() throws {
        let json = #"""
        {"type":"note","href":"notes.xhtml#n1","mark":{"x":300,"y":200,"width":8,"height":12},\#
        "font":{"family":"Georgia, serif","size":18,"lineHeight":null},\#
        "blocks":[{"runs":[{"text":"A "},{"text":"note","italic":true}],"indent":0}]}
        """#
        guard case .note(let note) = try ReaderMessage.decode(json) else {
            Issue.record("Not a note")
            return
        }
        #expect(note.href == "notes.xhtml#n1")
        #expect(note.mark.y == 200)
        #expect(note.font.size == 18)
        #expect(note.font.lineHeight == nil)
        #expect(note.blocks[0].runs[1].italic == true)
    }

    @Test func openNoteClosesOnAnotherTapAndOnAPageMoving() async throws {
        let model = try await opened()
        let note = ReaderNote(href: "notes.xhtml#n1", mark: .init(x: 1, y: 1, width: 1, height: 1), font: .init(size: 16), blocks: [])
        let place = model.position

        model.handle(.note(note))
        #expect(model.note == note)
        model.handle(.tap(zone: "dismiss"))
        #expect(model.note == nil)

        model.handle(.note(note))
        model.handle(.note(note))
        #expect(model.note == nil, "A second mark's tap only closes the first")

        model.handle(.note(note))
        model.handle(.link(href: "two.xhtml"))
        #expect(model.note == nil)
        #expect(model.trip == nil, "A link's tap only closes the note")

        #expect(model.position == place)
    }

    @Test func goToNoteIsAJumpWithTheWayBack() async throws {
        let model = try await opened()
        let place = try #require(model.savedPlace)
        let note = ReaderNote(href: "OEBPS/notes.xhtml#n6", mark: .init(x: 1, y: 1, width: 1, height: 1), font: .init(size: 16), blocks: [])
        model.handle(.note(note))
        model.goToNote()
        #expect(model.note == nil)
        #expect(await eventually(timeout: .seconds(10)) { model.trip != nil })
        #expect(model.trip?.place == place)
        #expect(model.savedPlace == place, "Your place doesn't move")
    }
}
