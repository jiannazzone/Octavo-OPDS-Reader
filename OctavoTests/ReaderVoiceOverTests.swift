import Foundation
import Testing
import UIKit
import WebKit
@testable import Octavo

/// VoiceOver reads the page as one item (#74): which way its scrolls turn.
struct ReaderVoiceOverTests {
    @Test func aSwipeSidewaysTurnsByThePagesOwnSides() {
        for forward in [ReaderTurnSide.right, .left] {
            #expect(ReaderVoiceOverPage.side(for: .right, forward: forward) == .right)
            #expect(ReaderVoiceOverPage.side(for: .left, forward: forward) == .left)
        }
    }

    // Read All asks for the next page at the end of one: forward in the
    // book's own direction, as a swipe up is.
    @Test(arguments: [ReaderTurnSide.right, .left])
    func nextAndDownGoForwardInTheBook(forward: ReaderTurnSide) {
        #expect(ReaderVoiceOverPage.side(for: .next, forward: forward) == forward)
        #expect(ReaderVoiceOverPage.side(for: .down, forward: forward) == forward)
        #expect(ReaderVoiceOverPage.side(for: .previous, forward: forward) == forward.opposite)
        #expect(ReaderVoiceOverPage.side(for: .up, forward: forward) == forward.opposite)
    }

    // Two quick turns: each landing is said, so the last place heard is
    // where the second landed.
    @Test func eachQueuedTurnIsSaidWhereItLands() {
        let start = ContinuousClock.now
        var turns = ReaderVoiceOverTurns()
        turns.asked(at: start)
        turns.asked(at: start + .milliseconds(200))
        let said = [300, 600, 900].map { turns.landed(at: start + .milliseconds($0), byJump: false) }
        #expect(said == [true, true, false])
    }

    // A turn that never landed (a jump took over, or it timed out) leaves
    // nothing for a later move to be taken for.
    @Test func aJumpOrALateMoveIsNotSaid() {
        let start = ContinuousClock.now
        var turns = ReaderVoiceOverTurns()
        turns.asked(at: start)
        var said = [turns.landed(at: start + .milliseconds(100), byJump: true)]
        said.append(turns.landed(at: start + .milliseconds(200), byJump: false))
        turns.asked(at: start + .seconds(1))
        said.append(turns.landed(at: start + .seconds(5), byJump: false))
        said.append(turns.landed(at: start + .seconds(5) + .milliseconds(1), byJump: false))
        #expect(said == [false, false, false, false])
    }

    // A turn asked for long after one that never landed counts once.
    @Test func aStaleTurnIsForgottenByTheNext() {
        let start = ContinuousClock.now
        var turns = ReaderVoiceOverTurns()
        turns.asked(at: start)
        turns.asked(at: start + .seconds(10))
        let said = [300, 600].map { turns.landed(at: start + .seconds(10) + .milliseconds($0), byJump: false) }
        #expect(said == [true, false])
    }
}

/// The page item's words, selected as VoiceOver's Text Selection rotor
/// does, sent on to the book (#125).
@MainActor
struct ReaderVoiceOverSelectionTests {
    private final class Sent {
        var ranges: [NSRange] = []
    }

    private func page(_ words: String = "It is a truth universally acknowledged.") -> (ReaderVoiceOverPage.PageView, any UITextInput, Sent) {
        let view = ReaderVoiceOverPage.PageView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        let sent = Sent()
        view.select = { range, _ in sent.ranges.append(range) }
        view.setWords(words, voiceOverRunning: false)
        return (view, view.accessibilityTextInputResponder!, sent)
    }

    private func select(_ input: any UITextInput, _ location: Int, _ length: Int) {
        let start = input.position(from: input.beginningOfDocument, offset: location)!
        input.selectedTextRange = input.textRange(from: start, to: input.position(from: start, offset: length)!)
    }

    // Once the book's selection is no longer the item's (a finger selected
    // other words), the item lets its own go, so the same words go again.
    @Test func theSameWordsGoAgainOnceTheBooksSelectionMoved() {
        let (view, input, sent) = page()
        view.accessibilityElementDidBecomeFocused()
        select(input, 8, 5)
        view.clearSelection()
        select(input, 8, 5)
        #expect(sent.ranges == [NSRange(location: 8, length: 5), NSRange(location: 8, length: 5)])
    }

    // UIKit collapsing the text view's selection as focus moves to the bar
    // leaves the book's selection, and the bar, where they are.
    @Test func aChangeAfterFocusLeftIsNotSent() {
        let (view, input, sent) = page()
        view.accessibilityElementDidBecomeFocused()
        select(input, 8, 5)
        view.accessibilityElementDidLoseFocus()
        select(input, 8, 0)
        #expect(sent.ranges == [NSRange(location: 8, length: 5)])
        // Back on the item, the same words are sent again.
        view.accessibilityElementDidBecomeFocused()
        select(input, 8, 5)
        #expect(sent.ranges.count == 2)
    }

    @Test func unselectingIsSentButMovingTheCursorIsNot() {
        let (view, input, sent) = page()
        view.accessibilityElementDidBecomeFocused()
        select(input, 3, 0)
        select(input, 8, 5)
        select(input, 10, 0)
        select(input, 12, 0)
        #expect(sent.ranges == [NSRange(location: 8, length: 5), NSRange(location: 10, length: 0)])
    }

    // The book's selection gone (taken for a highlight): the item's goes
    // quietly, and new words replace the old quietly.
    @Test func clearingAndNewWordsSendNothing() {
        let (view, input, sent) = page()
        view.accessibilityElementDidBecomeFocused()
        select(input, 8, 5)
        view.clearSelection()
        view.setWords("A second page.", voiceOverRunning: true)
        #expect(sent.ranges.count == 1)
        #expect(input.selectedTextRange.flatMap(input.text(in:)) == "")
        let all = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)!
        #expect(input.text(in: all) == "A second page.")
    }

    @Test func aPageWithoutWordsHasNoTextInput() {
        let (view, _, _) = page()
        view.setWords(nil)
        #expect(view.accessibilityTextInputResponder == nil)
    }
}

/// The words `bridge.js` sends for the page VoiceOver reads (#74).
@MainActor
@Suite(.temporaryFiles, .serialized, .timeLimit(.minutes(1)))
struct ReaderVoiceOverBridgeTests {
    private static func book(chapter: String, rightToLeft: Bool = false) -> Data {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:uuid:7b0c5b2e-0000-4000-8000-000000000074</dc:identifier>
        <dc:title>Words</dc:title>
        <meta property="dcterms:modified">2026-11-14T00:00:00Z</meta>
        </metadata>
        <manifest><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine\(rightToLeft ? #" page-progression-direction="rtl""# : "")><itemref idref="one"/></spine>
        </package>
        """
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        return StoredZip.make([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/one.xhtml", Data(chapter.utf8)),
        ])
    }

    private static let chapter = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title><style>p { margin: 0 }</style></head><body>
    <h2>Chapter One</h2>
    <p>It is a <i>truth</i>   universally
    acknowledged.</p>
    <p>A second <span>paragraph</span>.<span hidden="hidden">Hidden words.</span><span aria-hidden="true">Unread words.</span></p>
    <div><p>Inside a box.</p></div>
    <p>Line one<br/>line two</p>
    </body></html>
    """#

    private func opened(_ data: Data) async throws -> ReaderModel {
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "words.epub")
        try data.write(to: url)
        let store = ReadingPositionStore(directory: directory.appending(path: "positions", directoryHint: .isDirectory))
        let book = ReaderBook(fileURL: url, id: "words")
        let model = ReaderModel(book: book, store: store, bookmarks: ReaderBookmarks(bookID: book.id, store: BookmarkStore(directory: directory.appending(path: "bookmarks", directoryHint: .isDirectory))))
        let opened = await eventually(timeout: .seconds(30)) { model.phase != .loading && model.pageWords != nil }
        #expect(opened, "\(model.phase) \(model.lastError ?? "")")
        return model
    }

    @Test func thePageIsItsWordsALineToAParagraphWithoutHiddenText() async throws {
        let model = try await opened(Self.book(chapter: Self.chapter))
        #expect(model.pageWords == """
        Chapter One
        It is a truth universally acknowledged.
        A second paragraph.
        Inside a box.
        Line one
        line two
        """)
        #expect(model.forwardSide == .right)
    }

    // VoiceOver's Text Selection rotor picks words in the page's item: the
    // same words are selected in the book (#125), across markup, a run of
    // spaces made one, and a paragraph's end.
    @Test(arguments: [
        ("truth universally", "truth universally"),
        ("acknowledged.\nA second", "acknowledged. A second"),
        ("Line one\nline", "Line oneline"),
    ])
    func wordsSelectedInThePageSelectTheBook(picked: String, selected: String) async throws {
        let model = try await opened(Self.book(chapter: Self.chapter))
        let words = try #require(model.pageWords)
        let range = (words as NSString).range(of: picked)
        try #require(range.location != NSNotFound)
        model.selectPageWords(range, in: words)
        #expect(await eventually(timeout: .seconds(5)) { model.selectionBox != nil })
        let taken = try await model.page.callJavaScript("return await window.octavo.takeSelection()") as? [String: Any]
        #expect(taken?["text"] as? String == selected)
    }

    // Words from a page since turned select nothing; an empty range clears
    // the selection.
    @Test func staleWordsSelectNothingAndAnEmptyRangeClears() async throws {
        let model = try await opened(Self.book(chapter: Self.chapter))
        let words = try #require(model.pageWords)
        let stale = try await model.page.callJavaScript("return await window.octavo.selectPageWords(0, 5, text)", arguments: ["text": words + " "]) as? Bool
        #expect(stale == false)
        model.selectPageWords(NSRange(location: 0, length: 7), in: words)
        #expect(await eventually(timeout: .seconds(5)) { model.selectionBox != nil })
        model.selectPageWords(NSRange(location: 3, length: 0), in: words)
        #expect(await eventually(timeout: .seconds(5)) { model.selectionBox == nil })
    }

    // Unselecting in the page's item leaves a finger's selection made since.
    @Test func unselectingLeavesAFingersSelection() async throws {
        let model = try await opened(Self.book(chapter: Self.chapter))
        let words = try #require(model.pageWords)
        model.selectPageWords((words as NSString).range(of: "A second"), in: words)
        #expect(await eventually(timeout: .seconds(5)) { model.selectionBox != nil })
        let taken = try await model.page.callJavaScript("return await window.octavo.takeSelection()") as? [String: Any]
        let cfi = try #require(taken?["cfi"] as? String)
        #expect(await eventually(timeout: .seconds(5)) { model.selectionBox == nil })
        model.selectPageWords((words as NSString).range(of: "Inside"), in: words)
        #expect(await eventually(timeout: .seconds(5)) { model.selectionBox != nil && model.pageWordsSelected })
        // A finger selects other words: no longer the item's.
        _ = try await model.page.callJavaScript("return await window.octavo.selectRange(cfi)", arguments: ["cfi": cfi])
        #expect(await eventually(timeout: .seconds(5)) { model.selectionBox != nil && !model.pageWordsSelected })
        model.selectPageWords(NSRange(location: 0, length: 0), in: words)
        try await Task.sleep(for: .milliseconds(500))
        let left = try await model.page.callJavaScript("return await window.octavo.takeSelection()") as? [String: Any]
        #expect(left?["text"] as? String == "A second")
        // Each of VoiceOver's two selections said the bar came up; the
        // finger's didn't.
        #expect(model.barAnnouncements == 2)
    }

    @Test func aRightToLeftBookGoesForwardByTheLeftPage() async throws {
        let model = try await opened(Self.book(chapter: Self.chapter, rightToLeft: true))
        #expect(model.forwardSide == .left)
    }
}
