import Foundation
import Testing
import UIKit
import WebKit
@testable import Octavo

/// Pictures stay inside their text column, whatever size the book gives them
/// or the box around them, through the real bridge and foliate in a page
/// that's never shown (`docs/notes/reader-pictures.md`). The tests share the
/// page and reload it, because a new page takes about 1.6 s and a reload about
/// 35 ms (`docs/notes/ci.md`). A reload starts the scripts again.
@MainActor
@Suite(.temporaryFiles, .serialized, .timeLimit(.minutes(1)))
struct ReaderPicturesTests {
    /// The reader's view in each posture, Medium margins.
    struct Page: Sendable, CustomTestStringConvertible {
        var name: String
        var width: Double
        var height: Double
        var columns: Int
        var testDescription: String { name }
        /// foliate makes a spread only if a column may be this narrow.
        var maxInlineSize: Double { (width / Double(columns)).rounded(.up) }

        static let folded = Page(name: "folded", width: 382, height: 644, columns: 1)
        static let unfolded = Page(name: "unfolded", width: 783, height: 635, columns: 2)
        static let sideways = Page(name: "sideways", width: 669, height: 835, columns: 1)
    }

    /// What the probe reads off one element, in points.
    struct Box: Decodable {
        var width: Double
        var over: Double
    }

    struct Measured: Decodable {
        var column: Double
        var columns: Int
        var boxes: [String: Box]
        var maxWidths: [String: String]

        /// A box of text may run out of the column; a picture or its box may not.
        var tooWide: [String: Box] {
            boxes.filter { $0.key != "text-box" && $0.value.over > 0.5 }
        }
    }

    private static let chapter = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Pictures</title><style>
    .figcenter { margin: 3% auto; clear: both; text-align: center; }
    </style></head><body>
    <p>Text before the pictures.</p>
    <div id="gutenberg-box" class="figcenter" style="width: 550px;"><img id="gutenberg" alt="" src="big.png"/><p id="gutenberg-caption">A caption long enough to run out of a box that is too wide for the column.</p></div>
    <div class="figcenter" style="width: 550px;"><img id="small-in-box" alt="" src="small.png"/></div>
    <div id="margin-box" style="width: 30em; margin-left: 2em; padding: 0 1em;"><img id="margin" alt="" src="big.png"/></div>
    <table id="table-box" style="width: 800px;"><tr><td><img id="table" alt="" src="big.png"/></td></tr></table>
    <figure id="table-display-box" style="display: table; width: 600px;"><img id="table-display" alt="" src="big.png"/></figure>
    <table id="auto-table-box"><tr><td><img id="auto-table" alt="" src="big.png"/></td></tr></table>
    <div id="small-float-box" style="float: left;"><img id="small-float" alt="" src="big.png" style="max-width: 60px;"/></div>
    <p style="clear: both;">Text after the float.</p>
    <img id="zero-limit" alt="" src="big.png" style="max-width: 0;"/>
    <img id="own-limit" alt="" src="big.png" style="max-width: 800px;"/>
    <img id="percent-limit" alt="" src="big.png" style="max-width: 40%;"/>
    <img id="plain" alt="" src="big.png"/>
    <div id="text-box" style="width: 600px;">A box of text with no picture in it keeps the width the book gave it.</div>
    </body></html>
    """#

    /// A pre-paginated page that places what it draws: a picture and a table
    /// run out of a small box, past where the limits would stop them.
    private static let fixedLayoutPage = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Placed</title>
    <meta name="viewport" content="width=1000, height=1400"/></head><body>
    <div style="width: 100px;"><img id="placed" alt="" src="big.png" style="width: 800px; max-width: 800px;"/>
    <table id="placed-table" style="width: 600px;"><tr><td><img alt="" src="small.png"/></td></tr></table></div>
    </body></html>
    """#

    private static func picture(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private static func book(page: String = chapter, rendition: String = "") -> Data {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:uuid:7b0c5b2e-0000-4000-8000-000000000002</dc:identifier>
        <dc:title>Pictures</dc:title>
        <meta property="dcterms:modified">2026-11-04T00:00:00Z</meta>
        \(rendition)
        </metadata>
        <manifest>
        <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
        <item id="big" href="big.png" media-type="image/png"/>
        <item id="small" href="small.png" media-type="image/png"/>
        </manifest>
        <spine><itemref idref="c1"/></spine>
        </package>
        """
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        return StoredZip.make([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/c1.xhtml", Data(page.utf8)),
            ("OEBPS/big.png", picture(width: 1200, height: 800)),
            ("OEBPS/small.png", picture(width: 200, height: 100)),
        ])
    }

    private static let chapterBook = book()

    /// Outlasts each test's temporary folder. The next run's sweep removes it.
    private static let bookFile = URL.temporaryDirectory.appending(path: "\(TemporaryFiles.prefix)\(UUID().uuidString).epub")

    private static let sharedPage: WebPage = {
        var configuration = WebPage.Configuration()
        configuration.urlSchemeHandlers[URLScheme(ReaderSchemeHandler.scheme)!] = ReaderSchemeHandler(bookFile: bookFile)
        return WebPage(configuration: configuration)
    }()

    /// The reader's page with `book` open at `page`'s size. The page has no
    /// window, so its style sheet sets the view's size. With
    /// `renderingBeforeLoad` foliate renders each section just before the bridge
    /// hears of it, as its ResizeObserver may. Its `load` event stays in a closed
    /// shadow root, so nothing outside can listen for it.
    private func open(_ book: Data = chapterBook, at page: Page, renderingBeforeLoad: Bool = false) async throws -> WebPage {
        try book.write(to: Self.bookFile)
        let web = Self.sharedPage
        if web.url == nil {
            for try await _ in web.load(ReaderSchemeHandler.readerURL) {}
        } else {
            for try await _ in web.reload() {}
        }
        // The bridge is a module, which may finish after the document.
        while try await web.callJavaScript("return window.octavo !== undefined") as? Bool != true {
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try await web.callJavaScript("""
            const style = document.createElement('style')
            style.id = 'size'
            document.head.append(style)
            """)
        try await size(web, to: page)
        if renderingBeforeLoad {
            _ = try await web.callJavaScript("""
                const dispatch = EventTarget.prototype.dispatchEvent
                EventTarget.prototype.dispatchEvent = function (event) {
                    if (event.type === 'load' && event.detail?.doc) this.render?.()
                    return dispatch.call(this, event)
                }
                """)
        }
        _ = try await web.callJavaScript("return await window.octavo.open(options)", arguments: ["options": [
            "url": ReaderSchemeHandler.bookURL(fileName: Self.bookFile.lastPathComponent).absoluteString,
            "name": Self.bookFile.lastPathComponent,
            "layout": ["columns": page.columns, "gapPercent": 7, "maxInlineSize": page.maxInlineSize],
        ] as [String: Any]])
        return web
    }

    private func size(_ web: WebPage, to page: Page) async throws {
        _ = try await web.callJavaScript("""
            document.getElementById('size').textContent = `foliate-view {
                inset: 0 auto auto 0 !important; width: ${width}px !important; height: ${height}px !important;
            }`
            """, arguments: ["width": page.width, "height": page.height])
    }

    /// Every element with an id: its width, and how far any part of it runs
    /// past the sides of its column. A box that breaks across columns has a
    /// rect in each.
    private func measure(_ web: WebPage) async throws -> Measured {
        let json = try #require(try await web.callJavaScript("""
            const { doc } = document.querySelector('foliate-view').renderer.getContents()[0]
            await Promise.all([...doc.images].map(image => image.complete ? null
                : new Promise(resolve => { image.onload = image.onerror = resolve })))
            const root = doc.defaultView.getComputedStyle(doc.documentElement)
            const column = parseFloat(doc.defaultView.getComputedStyle(doc.body).width)
            const pitch = column + parseFloat(root.columnGap)
            const start = parseFloat(root.paddingLeft)
            const boxes = {}, maxWidths = {}
            for (const element of doc.body.querySelectorAll('[id]')) {
                const rects = [...element.getClientRects()]
                const over = rects.map(box => {
                    const left = (box.left - start) - Math.floor((box.left - start + 0.5) / pitch) * pitch
                    return Math.max(left + box.width - column, -left, 0)
                })
                boxes[element.id] = { width: rects[0].width, over: Math.max(...over) }
                maxWidths[element.id] = element.style.maxWidth
            }
            const columns = document.querySelector('foliate-view').renderer.heads?.length ?? 0
            return JSON.stringify({ column, columns, boxes, maxWidths })
            """) as? String)
        return try JSONDecoder().decode(Measured.self, from: Data(json.utf8))
    }

    @Test(arguments: [Page.folded, .unfolded, .sideways])
    func picturesAndTheirBoxesFitTheColumn(page: Page) async throws {
        let web = try await open(at: page)
        let measured = try await measure(web)
        #expect(measured.tooWide.isEmpty, "\(measured.tooWide) in a column of \(measured.column)")
        // The illustration that started this: as wide as its box, which is as
        // wide as the book says or the column allows.
        #expect(measured.columns == page.columns)
        #expect(abs(try #require(measured.boxes["gutenberg"]).width - min(550, measured.column)) < 0.5)
    }

    @Test(arguments: [Page.folded, .unfolded, .sideways])
    func picturesThatAlreadyFitKeepTheirSize(page: Page) async throws {
        let web = try await open(at: page)
        let measured = try await measure(web)
        #expect(try #require(measured.boxes["small-in-box"]).width == 200)
        #expect(abs(try #require(measured.boxes["percent-limit"]).width - measured.column * 0.4) < 0.5)
        #expect(abs(try #require(measured.boxes["plain"]).width - measured.column) < 0.5)
        // foliate takes a limit of 0 to mean none.
        #expect(abs(try #require(measured.boxes["zero-limit"]).width - measured.column) < 0.5)
        // A float takes its size from a small picture, so text can wrap beside it.
        #expect(try #require(measured.boxes["small-float-box"]).width == 60)
    }

    // Text is laid out as the book says, only boxes with a picture change.
    @Test func aBoxOfTextKeepsItsWidth() async throws {
        let web = try await open(at: .folded)
        #expect(try await measure(web).boxes["text-box"]?.width == 600)
    }

    // A fixed-layout page places its pictures itself, so nothing limits them.
    @Test func fixedLayoutPagesKeepWhatTheyPlace() async throws {
        let book = Self.book(page: Self.fixedLayoutPage, rendition: #"<meta property="rendition:layout">pre-paginated</meta>"#)
        let web = try await open(book, at: .folded)
        let widths = try #require(try await web.callJavaScript("""
            const view = document.querySelector('foliate-view')
            const doc = view.renderer.getContents().map(content => content.doc).find(doc => doc?.getElementById('placed'))
            await Promise.all([...doc.images].map(image => image.complete ? null
                : new Promise(resolve => { image.onload = image.onerror = resolve })))
            const width = id => doc.getElementById(id).getBoundingClientRect().width
            return { fixed: view.isFixedLayout, picture: width('placed'), table: width('placed-table') }
            """) as? [String: Any])
        #expect(widths["fixed"] as? Bool == true)
        #expect(widths["picture"] as? Double == 800)
        #expect(widths["table"] as? Double == 600)
    }

    // Unfolding or turning the device lays the same document out again. Whether
    // foliate's ResizeObserver rendered the section before it loaded or not, which
    // is up to chance in the real thing: a render before `load` would pin the table
    // to that layout (patch 0004), about once in 100 opens.
    @Test(arguments: [false, true])
    func picturesStillFitWhenThePageChangesSize(renderingBeforeLoad: Bool) async throws {
        let web = try await open(at: .folded, renderingBeforeLoad: renderingBeforeLoad)
        let limit = try await measure(web).maxWidths["own-limit"]
        for page in [Page.unfolded, .sideways, .unfolded] {
            try await size(web, to: page)
            _ = try await web.callJavaScript("""
                const renderer = document.querySelector('foliate-view').renderer
                renderer.setAttribute('max-column-count', columns)
                renderer.setAttribute('max-column-count-portrait', columns)
                renderer.setAttribute('max-inline-size', `${maxInlineSize}px`)
                renderer.render()
                """, arguments: ["columns": page.columns, "maxInlineSize": page.maxInlineSize])
            let measured = try await measure(web)
            #expect(measured.tooWide.isEmpty, "\(measured.tooWide) in a column of \(measured.column), \(page.name)")
            #expect(measured.maxWidths["own-limit"] == limit)
            // A table with no width of its own isn't pinned to its first layout.
            let table = try #require(measured.boxes["auto-table-box"])
            #expect(abs(table.width - measured.column) < 1, "\(table.width) in a column of \(measured.column), \(page.name)")
        }
    }
}
