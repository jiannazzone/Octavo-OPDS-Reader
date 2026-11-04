import Foundation
import OctavoKit
import Testing
import WebKit
@testable import Octavo

/// Pre-paginated books through the bridge, in a page that's never shown
/// (`docs/notes/fixed-layout.md`). Each opens a real book in a real page.
@MainActor
@Suite(.temporaryFiles)
struct ReaderFixedLayoutTests {
    private let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private let bookmarkStore = BookmarkStore(
        directory: URL.testDirectory.appending(path: "bookmarks-\(UUID().uuidString)", directoryHint: .isDirectory)
    )

    /// Twelve 1000×1400 pages whose files differ in size, as a real book's do
    /// (foliate's fractions count bytes). Page 5 tries to run a script.
    private static func book(spread: String = "auto") -> Data {
        let items = (1...12).map { #"<item id="p\#($0)" href="p\#($0).xhtml" media-type="application/xhtml+xml"/>"# }.joined()
        let refs = (1...12).map { #"<itemref idref="p\#($0)"/>"# }.joined()
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:octavo:fixed-layout-test</dc:identifier>
        <dc:title>Fixed layout</dc:title>
        <dc:language>en</dc:language>
        <meta property="dcterms:modified">2026-11-04T00:00:00Z</meta>
        <meta property="rendition:layout">pre-paginated</meta>
        <meta property="rendition:spread">\(spread)</meta>
        </metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\(items)</manifest>
        <spine>\(refs)</spine>
        </package>
        """
        let nav = #"<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="p1.xhtml">Front</a></li><li><a href="p4.xhtml">Middle</a></li></ol></nav></body></html>"#
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        let pages = (1...12).map { number -> (String, Data) in
            let filler = (0..<(number * number * 20)).map { "word\($0)" }.joined(separator: " ")
            let script = number == 5 ? "<script>document.documentElement.setAttribute('data-ran', 'script')</script>" : ""
            let page = """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Page \(number)</title>
            <meta name="viewport" content="width=1000, height=1400"/>\(script)</head>
            <body><p>Page \(number)</p><p>\(filler)</p></body></html>
            """
            return ("OEBPS/p\(number).xhtml", Data(page.utf8))
        }
        return StoredZip.make([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/nav.xhtml", Data(nav.utf8)),
        ] + pages)
    }

    private func open(_ data: Data = book(), saved: ReadingPosition? = nil) async throws -> ReaderModel {
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "fixed.epub")
        try data.write(to: url)
        let book = ReaderBook(fileURL: url, id: "fixed")
        if let saved { try store.save(saved, forBook: book.id) }
        let model = ReaderModel(book: book, store: store, bookmarks: ReaderBookmarks(bookID: book.id, store: bookmarkStore))
        let opened = await eventually(timeout: .seconds(30)) { model.phase != .loading && model.relocation != nil }
        #expect(opened, "\(model.phase) \(model.lastError ?? "")")
        // The page isn't on screen, so it draws no frames; these don't wait for one.
        _ = try await model.page.callJavaScript("window.requestAnimationFrame = f => setTimeout(f, 16)")
        return model
    }

    private func script<T>(_ model: ReaderModel, _ body: String, arguments: [String: Any] = [:]) async throws -> T? {
        try await model.page.callJavaScript(body, arguments: arguments) as? T
    }

    /// The page on screen, from 0.
    private func page(_ model: ReaderModel) -> Int? { model.relocation?.sectionIndex }

    private func go(_ model: ReaderModel, toPage index: Int) async {
        model.goTo(cfi: Self.cfi(index))
        #expect(await eventually(timeout: .seconds(10)) { page(model) == index })
    }

    private static func cfi(_ index: Int) -> String { "epubcfi(/6/\((index + 1) * 2))" }

    private func fractions(_ model: ReaderModel) async throws -> [Double] {
        try #require(await script(model, "return document.querySelector('foliate-view').getSectionFractions()"))
    }

    /// Sized as a folded phone's reader (one page) or a spread (two).
    private func size(_ model: ReaderModel, width: Int, height: Int) async throws {
        let _: Bool? = try await script(model, """
        Object.assign(document.querySelector('foliate-view').style, { left: '0', top: '0', right: 'auto', bottom: 'auto', width: '\(width)px', height: '\(height)px' })
        return true
        """)
    }

    // MARK: Opening

    @Test func opensOnTheFirstPage() async throws {
        let model = try await open()
        #expect(model.phase == .open)
        #expect(model.isFixedLayout)
        #expect(model.restoredFrom == "start")
        #expect(page(model) == 0)
        #expect(model.lastError == nil)
    }

    // A relocation's fraction used to carry each open a page on.
    @Test func reopensOnTheSamePageEveryTime() async throws {
        var position = ReadingPosition(cfi: Self.cfi(5), fraction: 0.1)
        for _ in 0..<3 {
            let model = try await open(saved: position)
            #expect(model.restoredFrom == "cfi")
            #expect(page(model) == 5)
            position = try #require(model.position)
            #expect(position.cfi == Self.cfi(5))
        }
    }

    // BookOrbit's web reader goes by this number alone.
    @Test(arguments: [0, 2, 5, 10])
    func theSavedFractionIsInsideThePage(index: Int) async throws {
        let model = try await open()
        await go(model, toPage: index)
        let bounds = try await fractions(model)
        let fraction = try #require(model.position?.fraction)
        #expect(fraction > bounds[index] && fraction < bounds[index + 1])

        let reopened = try await open(saved: ReadingPosition(cfi: nil, fraction: fraction))
        #expect(reopened.restoredFrom == "fraction")
        #expect(page(reopened) == index)
    }

    @Test func theLastPageIsTheEnd() async throws {
        let model = try await open()
        await go(model, toPage: 11)
        #expect(model.position?.fraction == 1)
    }

    // What the web reader saved, without its CFI: a section's end, as a
    // 32-bit percentage, which can round up past it.
    @Test(arguments: [1, 2, 7, 8, 9])
    func aServersSectionEndIsThatPage(index: Int) async throws {
        let bounds = try await fractions(try await open())
        let percent = Float(bounds[index + 1] * 100)
        let model = try await open(saved: ReadingPosition(cfi: nil, fraction: Double(percent) / 100))
        #expect(model.restoredFrom == "fraction")
        #expect(page(model) == index)
    }

    @Test func aCFIThisBookDoesntHaveFallsBackToTheFraction() async throws {
        let bounds = try await fractions(try await open())
        let inside = (bounds[3] + bounds[4]) / 2
        let model = try await open(saved: ReadingPosition(cfi: "epubcfi(/6/999)", fraction: inside))
        #expect(model.restoredFrom == "fraction")
        #expect(page(model) == 3)
        let went: Bool? = try await script(model, "return await window.octavo.goTo('epubcfi(/6/999)')")
        #expect(went == false)
        #expect(page(model) == 3)
    }

    // MARK: Where the page is

    @Test func onPageAsksBySection() async throws {
        let model = try await open()
        await go(model, toPage: 5)
        let cfis = [4, 5, 6, 7].map(Self.cfi) + ["not a cfi"]
        try await size(model, width: 800, height: 500)
        let spread: [Bool]? = try await script(model, "return await window.octavo.onPage(cfis)", arguments: ["cfis": cfis])
        #expect(spread == [false, true, true, false, false])
        try await size(model, width: 300, height: 600)
        let one: [Bool]? = try await script(model, "return await window.octavo.onPage(cfis)", arguments: ["cfis": cfis])
        #expect(one == [false, true, false, false, false])
    }

    // foliate's patch 0003.
    @Test func goingToTheOtherPageOfASpreadMoves() async throws {
        let model = try await open()
        try await size(model, width: 300, height: 600)
        await go(model, toPage: 5)
        await go(model, toPage: 6)
        #expect(model.position?.cfi == Self.cfi(6))
    }

    @Test func aPlaceIsDescribedByItsSection() async throws {
        let model = try await open()
        let place = try #require(await model.describe(Self.cfi(5)))
        #expect(place.chapter == "Middle")
        #expect(place.excerpt?.hasPrefix("Page 6") == true)
    }

    // MARK: Layout

    // `setLayout` called the paginator's `render`, which this renderer doesn't
    // have, so a fold's hold never ended.
    @Test func aFoldsHoldEnds() async throws {
        let model = try await open()
        try await size(model, width: 300, height: 600)
        await go(model, toPage: 2)
        let held: Bool? = try await script(model, "return await window.octavo.hold()")
        #expect(held == true)
        model.goTo(cfi: Self.cfi(4))
        try await Task.sleep(for: .milliseconds(500))
        #expect(page(model) == 2)

        let layout = ReaderLayout(columns: 2, gapPercent: 7, maxInlineSize: 392, leftInset: 84, rightInset: 84)
        let rendered: Bool? = try await script(model, "return await window.octavo.setLayout(layout)", arguments: ["layout": layout.scriptArguments])
        #expect(rendered == true)
        #expect(await eventually { page(model) == 4 })
        #expect(model.lastError == nil)
    }

    // A book's `rendition:spread` would otherwise put two tiny pages on the
    // folded phone.
    @Test func oneColumnIsOnePageWhateverTheBookAsks() async throws {
        let model = try await open(Self.book(spread: "both"))
        try await size(model, width: 300, height: 600)
        let one = ReaderLayout(columns: 1)
        let _: Bool? = try await script(model, "return await window.octavo.setLayout(layout)", arguments: ["layout": one.scriptArguments])
        let folded: String? = try await script(model, "return document.querySelector('foliate-view').renderer.spread")
        #expect(folded == "landscape")
        let two = ReaderLayout(columns: 2)
        let _: Bool? = try await script(model, "return await window.octavo.setLayout(layout)", arguments: ["layout": two.scriptArguments])
        let unfolded: String? = try await script(model, "return document.querySelector('foliate-view').renderer.spread")
        #expect(unfolded == "both")
    }

    // Narrow margins reach under the side column, with nothing to keep the
    // page out of it.
    @Test func marginsDontMoveThePage() async throws {
        let model = try await open()
        model.margins = .narrow
        model.safeAreaChanged(ReaderInsets(right: 84))
        model.hingeChanged(.closed, angle: 0)
        model.geometryChanged(ReaderGeometry(size: CGSize(width: 466, height: 678)))
        #expect(await eventually {
            model.layout == ReaderLayout(posture: .closed, geometry: model.geometry, margins: .standard)
        })
        #expect(model.layout.rightInset == 84)
    }

    // A section's frame is scaled to fit, so a tap's coordinates inside it
    // are larger than the screen's.
    @Test func aTapGoesByWhereItIsOnTheScreen() async throws {
        let model = try await open()
        try await size(model, width: 382, height: 644)
        await go(model, toPage: 5)
        let tap = """
        const doc = document.querySelector('foliate-view').renderer.getContents().find(c => c.doc.title).doc
        const scale = (() => { const f = doc.defaultView.frameElement; return f.getBoundingClientRect().width / f.offsetWidth })()
        const options = { clientX: x / scale, clientY: 100, screenX: x, screenY: 100, isPrimary: true, pointerId: 1, bubbles: true }
        doc.dispatchEvent(new PointerEvent('pointerdown', options))
        doc.dispatchEvent(new PointerEvent('pointerup', options))
        return scale
        """
        // Left of the page's middle (191): 120 on screen is 314 in the frame.
        let scale: Double? = try await script(model, tap, arguments: ["x": 120])
        #expect((scale ?? 1) < 0.5)
        #expect(await eventually(timeout: .seconds(10)) { page(model) == 4 })
    }

    // MARK: The footer

    private func setLayout(_ model: ReaderModel, _ layout: ReaderLayout) async throws {
        let _: Bool? = try await script(model, "return await window.octavo.setLayout(layout)", arguments: ["layout": layout.scriptArguments])
    }

    private func place(_ model: ReaderModel) -> ReaderPlace {
        ReaderPlace(chapter: model.chapter, location: model.location, fraction: model.shownFraction)
    }

    @Test func theFooterCountsTheBooksPages() async throws {
        let model = try await open()
        try await size(model, width: 300, height: 600)
        await go(model, toPage: 5)
        #expect(place(model).footer(spread: false) == "6 of 12 · 50%")
        #expect(place(model).barLine(spread: false) == "Page 6 of 12 · 50%")
        // What's saved still suits BookOrbit: this page's share of the bytes.
        let saved = try #require(model.position?.fraction)
        #expect(saved < 0.2)
    }

    // A re-layout shows more pages, which foliate doesn't report.
    @Test func unfoldingCountsTheSpread() async throws {
        let model = try await open()
        try await size(model, width: 300, height: 600)
        await go(model, toPage: 5)
        let count = model.relocationCount
        let layout = ReaderLayout(columns: 2, gapPercent: 7, maxInlineSize: 392, leftInset: 84, rightInset: 84)
        // Two pages take a wider view than this page has: a spread's own shape.
        try await size(model, width: 800, height: 500)
        try await setLayout(model, layout)
        #expect(await eventually { model.relocationCount > count })
        #expect(place(model).footer(spread: true) == "6–7 of 12 · 58%")
        #expect(model.position?.cfi == Self.cfi(5))
    }

    @Test func theLastPageIsAllOfTheBook() async throws {
        let model = try await open()
        await go(model, toPage: 11)
        #expect(place(model).percent == "100%")
    }

    // The slider's label and where it lands have to agree.
    @Test(arguments: [(0.0, 0), (0.3, 3), (0.5, 6), (0.99, 11), (1.0, 11)])
    func theBarGoesByPages(fraction: Double, index: Int) async throws {
        let model = try await open()
        try await size(model, width: 300, height: 600)
        await go(model, toPage: 1)
        let total = try #require(model.location?.total)
        #expect(ReaderModel.page(at: fraction, total: total) == index + 1)
        model.goTo(fraction: fraction)
        #expect(await eventually(timeout: .seconds(10)) { page(model) == index })
    }

    @Test func theContentsCountTheBooksPages() async throws {
        let model = try await open()
        #expect(await eventually(timeout: .seconds(10)) { model.toc.count == 2 })
        #expect(model.contentsRows.map(\.page) == [1, 4])
    }

    // A chapter's last page, whose end is where the next chapter starts, is
    // still in its chapter.
    @Test func aChaptersLastPageIsInIt() async throws {
        let model = try await open()
        try await size(model, width: 300, height: 600)
        #expect(await eventually(timeout: .seconds(10)) { model.toc.count == 2 })
        await go(model, toPage: 2)
        let last = try #require(ReaderChapterProgress(place: place(model), toc: model.toc))
        #expect(last.pagesLeft == 0)
        await go(model, toPage: 3)
        let first = try #require(ReaderChapterProgress(place: place(model), toc: model.toc))
        #expect(first.pagesLeft == 8)
    }

    // MARK: Scripts

    @Test func aBooksScriptsNeverRun() async throws {
        let model = try await open()
        await go(model, toPage: 4)
        let ran: [String]? = try await script(model, """
        return document.querySelector('foliate-view').renderer.getContents().map(c => c.doc.documentElement?.getAttribute('data-ran')).filter(Boolean)
        """)
        #expect(ran == [])
    }
}
