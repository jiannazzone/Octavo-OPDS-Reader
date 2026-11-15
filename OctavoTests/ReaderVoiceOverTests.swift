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

    // Without VoiceOver (as in tests), Voice Control and Switch Control get
    // Next Page and Previous Page over the page's sides, Next forward (#75).
    @MainActor @Test func withoutVoiceOverTheSidesAreTurnButtons() {
        let view = ReaderVoiceOverPage.PageView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        view.layoutIfNeeded()
        var turned: [ReaderTurnSide] = []
        view.turn = { side in
            turned.append(side)
            return true
        }
        let elements = view.accessibilityElements?.compactMap { $0 as? UIAccessibilityElement } ?? []
        #expect(elements.count == 3)
        #expect(elements.first?.accessibilityLabel == "Previous Page")
        #expect(elements.last?.accessibilityLabel == "Next Page")
        #expect(elements.last?.accessibilityFrameInContainerSpace == CGRect(x: 300, y: 0, width: 100, height: 600))
        #expect(elements[1].accessibilityTraits.contains(.causesPageTurn))
        #expect(elements.first?.accessibilityActivate() == true)
        #expect(elements.last?.accessibilityActivate() == true)
        #expect(turned == [.left, .right])

        view.forward = .left
        #expect(elements.first?.accessibilityLabel == "Next Page")
        #expect(elements.last?.accessibilityLabel == "Previous Page")

        // Folded, the side column covers the page's right edge: the button
        // stays clear of it, or Voice Control leaves it out.
        view.safeArea = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        view.layoutIfNeeded()
        #expect(elements.last?.accessibilityFrameInContainerSpace == CGRect(x: 237, y: 0, width: 79, height: 566))
        #expect(elements.first?.accessibilityFrameInContainerSpace == CGRect(x: 0, y: 0, width: 79, height: 566))
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

    @Test func aRightToLeftBookGoesForwardByTheLeftPage() async throws {
        let model = try await opened(Self.book(chapter: Self.chapter, rightToLeft: true))
        #expect(model.forwardSide == .left)
    }
}
