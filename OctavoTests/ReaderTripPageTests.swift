import Foundation
import OctavoKit
import Testing
import UIKit
import WebKit
@testable import Octavo

/// Going back through the bridge, in a page that's never shown (decision 33).
@MainActor
@Suite(.temporaryFiles)
struct ReaderTripPageTests {
    private let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private let bookmarkStore = BookmarkStore(
        directory: URL.testDirectory.appending(path: "bookmarks-\(UUID().uuidString)", directoryHint: .isDirectory)
    )

    /// Two chapters. The first links to the second and out of the book.
    private static func book() -> Data {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:octavo:trip-test</dc:identifier>
        <dc:title>Trips</dc:title>
        <dc:language>en</dc:language>
        <meta property="dcterms:modified">2026-11-04T00:00:00Z</meta>
        </metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\
        <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>\
        <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="one"/><itemref idref="two"/></spine>
        </package>
        """
        let nav = #"<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="one.xhtml">One</a></li><li><a href="two.xhtml">Two</a></li></ol></nav></body></html>"#
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        func chapter(_ title: String, _ links: String) -> Data {
            let words = (0..<2000).map { "word\($0)" }.joined(separator: " ")
            return Data(#"<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>\#(title)</title></head><body><h1>\#(title)</h1>\#(links)<p>\#(words)</p></body></html>"#.utf8)
        }
        return StoredZip.make([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/nav.xhtml", Data(nav.utf8)),
            ("OEBPS/one.xhtml", chapter("One", #"<p><a id="inside" href="two.xhtml">Two</a> <a id="outside" href="https://example.org/">Out</a></p>"#)),
            ("OEBPS/two.xhtml", chapter("Two", "")),
        ])
    }

    private static let bookID = "trips"

    private func open() async throws -> ReaderModel {
        let model = try start()
        let opened = await eventually(timeout: .seconds(30)) { model.phase != .loading && model.relocation != nil }
        #expect(opened, "\(model.phase) \(model.lastError ?? "")")
        // The page isn't on screen, so it draws no frames; these don't wait for one.
        _ = try await model.page.callJavaScript("window.requestAnimationFrame = f => setTimeout(f, 16)")
        return model
    }

    /// Opening by a CFI waits for frames, so it never says it's opened here:
    /// the relocation says where it went, and the test says the rest.
    private func reopen(sync: (any ProgressSync)? = nil) async throws -> ReaderModel {
        let model = try start(sync: sync)
        #expect(await eventually(timeout: .seconds(30)) { model.relocation != nil })
        model.handle(.opened(.init(restoredFrom: "cfi", sectionCount: 2, isFixedLayout: false)))
        return model
    }

    private func start(sync: (any ProgressSync)? = nil) throws -> ReaderModel {
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "trips.epub")
        try Self.book().write(to: url)
        return ReaderModel(
            book: ReaderBook(fileURL: url, id: Self.bookID), store: store, sync: sync,
            bookmarks: ReaderBookmarks(bookID: Self.bookID, store: bookmarkStore), pushDelay: .milliseconds(50)
        )
    }

    private func tap(_ link: String, in model: ReaderModel) async throws {
        _ = try await model.page.callJavaScript("""
        document.querySelector('foliate-view').renderer.getContents()[0].doc.querySelector(selector).click()
        return true
        """, arguments: ["selector": "#\(link)"])
    }

    @Test func aLinkInTheBookIsAJump() async throws {
        let model = try await open()
        let place = try #require(store.position(forBook: Self.bookID))
        try await tap("inside", in: model)
        #expect(await eventually(timeout: .seconds(10)) { model.trip != nil })
        #expect(model.relocation?.sectionIndex == 1)
        #expect(model.trip?.place == place)
        #expect(store.position(forBook: Self.bookID) == place)
    }

    @Test func aLinkOutOfTheBookGoesNowhere() async throws {
        let model = try await open()
        let place = model.position
        try await tap("outside", in: model)
        try await Task.sleep(for: .milliseconds(700))
        #expect(model.trip == nil)
        #expect(model.position == place)
        #expect(model.relocation?.sectionIndex == 0)
    }

    @Test func aTripReopensOnItsPage() async throws {
        let first = try await open()
        let place = try #require(store.position(forBook: Self.bookID))
        try await tap("inside", in: first)
        #expect(await eventually(timeout: .seconds(10)) { first.trip != nil })

        let reopened = try await reopen()
        #expect(reopened.relocation?.sectionIndex == 1)
        #expect(reopened.trip?.place == place)
        #expect(store.position(forBook: Self.bookID) == place)
    }

    /// Spelled as a page spells it or as the server did, it's your place.
    @Test func aPlaceTheServerSpellsItsOwnWayKeepsTheTrip() async throws {
        let first = try await open()
        try await tap("inside", in: first)
        #expect(await eventually(timeout: .seconds(10)) { first.trip != nil })
        var trip = try #require(store.trip(forBook: Self.bookID))
        let spelling = "epubcfi(/6/2!/4/2)"
        trip.placeOnServer = spelling
        store.saveTrip(trip, forBook: Self.bookID)

        let backend = FakeProgressSync(remote: SyncedPosition(position: ReadingPosition(cfi: spelling, fraction: 0), updatedAt: .now))
        let reopened = try await reopen(sync: backend)
        #expect(reopened.relocation?.sectionIndex == 1)
        #expect(reopened.trip?.placeOnServer == spelling)
    }

    @Test func anotherReaderMovingYourPlaceEndsTheTrip() async throws {
        let first = try await open()
        try await tap("inside", in: first)
        #expect(await eventually(timeout: .seconds(10)) { first.trip != nil })

        let moved = ReadingPosition(cfi: "epubcfi(/6/4!/4/4)", fraction: 0.6)
        let reopened = try await reopen(sync: FakeProgressSync(remote: SyncedPosition(position: moved, updatedAt: .now)))
        #expect(reopened.trip == nil)
        #expect(store.trip(forBook: Self.bookID) == nil)
    }

    /// A slider replaced under the finger sends no event of its own.
    @Test func aSliderTakenAwayMidTouchLetsGo() async throws {
        let window = UIWindow()
        let slider = ReaderScrubberSlider()
        window.addSubview(slider)
        var cancelled = false
        slider.onCancel = { cancelled = true }
        slider.sendActions(for: .touchDown)
        slider.removeFromSuperview()
        #expect(await eventually { cancelled })
    }

    @Test func aSliderTakenAwayUntouchedSaysNothing() async throws {
        let window = UIWindow()
        let slider = ReaderScrubberSlider()
        window.addSubview(slider)
        var cancelled = false
        slider.onCancel = { cancelled = true }
        slider.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!cancelled)
    }
}
