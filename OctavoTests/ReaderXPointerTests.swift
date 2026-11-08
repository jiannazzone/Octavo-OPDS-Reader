import Foundation
import OctavoKit
import Testing
import WebKit
@testable import Octavo

/// KOReader's places through the bridge (`bridge.js` `xpointerOf`,
/// `resolveXPointer`; `docs/notes/koreader-sync.md`), in a page that's never
/// shown. The counting rules were measured against KOReader v2026.07.1; this
/// checks the bridge follows them.
@MainActor
@Suite(.temporaryFiles)
struct ReaderXPointerTests {
    private let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )

    /// Two sections. The second is indented XHTML, as Moby-Dick's is, with a
    /// word in italics, whitespace runs, an emoji, a table without `<tbody>`,
    /// `<pre>`, and enough words for several pages.
    static func book() -> Data {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:octavo:xpointer-test</dc:identifier>
        <dc:title>Places</dc:title>
        <dc:language>en</dc:language>
        <meta property="dcterms:modified">2026-11-08T00:00:00Z</meta>
        </metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\
        <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>\
        <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="one"/><itemref idref="two"/></spine>
        </package>
        """
        let nav = #"<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="one.xhtml">One</a></li><li><a href="two.xhtml">Two</a></li></ol></nav></body></html>"#
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        let one = #"<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head><body><h1>One</h1><p>Opening words.</p></body></html>"#
        let words = (0..<3000).map { "word\($0)" }.joined(separator: " ")
        let two = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
          <head><title>Two</title></head>
          <body>
            <h1>Two</h1>
            <div>
              <p>First paragraph alpha.</p>
              <p>Second <i>paragraph</i> bravo charlie.</p>
              <p>
                Third paragraph,
                with   runs of    space delta echo.
              </p>
              <p>Emoji \u{1F642} then foxtrot golf.</p>
              <table><tr><td>Cell hotel</td></tr></table>
              <pre>  Pre  india   juliet</pre>
              <p>
        <span>W</span>hen kilo lima.</p>
              <p>&#160;<span>N</span>ovember oscar.</p>
              <p>\(words)</p>
            </div>
          </body>
        </html>
        """
        return StoredZip.make([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/nav.xhtml", Data(nav.utf8)),
            ("OEBPS/one.xhtml", Data(one.utf8)),
            ("OEBPS/two.xhtml", Data(two.utf8)),
        ])
    }

    private func start(sync: (any ProgressSync)? = nil) throws -> ReaderModel {
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "places.epub")
        try Self.book().write(to: url)
        return ReaderModel(book: ReaderBook(fileURL: url, id: "places"), store: store, sync: sync, pushDelay: .milliseconds(50))
    }

    private func open(sync: (any ProgressSync)? = nil) async throws -> ReaderModel {
        let model = try start(sync: sync)
        let opened = await eventually(timeout: .seconds(30)) { model.phase != .loading && model.relocation != nil }
        #expect(opened, "\(model.phase) \(model.lastError ?? "")")
        // The page isn't on screen, so it draws no frames; these don't wait for one.
        _ = try await model.page.callJavaScript("window.requestAnimationFrame = f => setTimeout(f, 16)")
        return model
    }

    private func resolve(_ xpointer: Any, in model: ReaderModel) async throws -> [String: Any]? {
        try await model.page.callJavaScript("return await window.octavo.resolveXPointer(x)", arguments: ["x": xpointer]) as? [String: Any]
    }

    /// The words a CFI starts at, as the Contents panel shows them.
    private func words(at cfi: String, in model: ReaderModel) async throws -> String {
        let place = try await model.page.callJavaScript("return await window.octavo.describe(cfi)", arguments: ["cfi": cfi]) as? [String: Any]
        return place?["excerpt"] as? String ?? ""
    }

    private func xpointer(at cfi: String, in model: ReaderModel) async throws -> String? {
        try await model.page.callJavaScript("return await window.octavo.xpointerAt(cfi)", arguments: ["cfi": cfi]) as? String
    }

    /// KOReader's place → the words it names → the place Octavo would send back.
    @Test(arguments: [
        ("/body/DocFragment[2]/body/div/p[1]/text().6", "paragraph alpha.", "/body/DocFragment[2]/body/div/p[1].0"),
        // `[1]`, as newer KOReader writes it, and tag names in capitals.
        ("/body/DocFragment[2]/body/div[1]/p[1]/text()[1].6", "paragraph alpha.", "/body/DocFragment[2]/body/div/p[1].0"),
        ("/body/DocFragment[2]/body/DIV/P[1].0", "First paragraph", "/body/DocFragment[2]/body/div/p[1].0"),
        // The text after the italics is the paragraph's second text node.
        ("/body/DocFragment[2]/body/div/p[2]/text()[2].1", "bravo charlie.", "/body/DocFragment[2]/body/div/p[2].0"),
        ("/body/DocFragment[2]/body/div/p[2]/i/text().0", "paragraph bravo", "/body/DocFragment[2]/body/div/p[2]/i.0"),
        // A run of spaces and line breaks is one character, the leading one too.
        ("/body/DocFragment[2]/body/div/p[3]/text().37", "delta echo.", "/body/DocFragment[2]/body/div/p[3].0"),
        // The emoji is one character to crengine and two in UTF-16.
        ("/body/DocFragment[2]/body/div/p[4]/text().13", "foxtrot golf.", "/body/DocFragment[2]/body/div/p[4].0"),
        // <pre> keeps its spaces.
        ("/body/DocFragment[2]/body/div/pre/text().7", "india juliet", "/body/DocFragment[2]/body/div/pre.0"),
        // The line break before a drop cap isn't a text node to KOReader.
        ("/body/DocFragment[2]/body/div/p[5]/text().4", "kilo lima.", "/body/DocFragment[2]/body/div/p[5].0"),
        // A no-break space is text to KOReader, before a drop cap too.
        ("/body/DocFragment[2]/body/div/p[6]/text()[2].0", "ovember oscar.", "/body/DocFragment[2]/body/div/p[6].0"),
        // Inside a table, the place sent back is the table.
        ("/body/DocFragment[2]/body/div/table/tr/td/text().5", "hotel", "/body/DocFragment[2]/body/div/table.0"),
        // Words that aren't there fall back to their element.
        ("/body/DocFragment[2]/body/div/p[2]/text()[9].0", "Second paragraph", "/body/DocFragment[2]/body/div/p[2].0"),
        // A section, as Komga sends it, and an element with no offset.
        ("/body/DocFragment[2].0", "Two First paragraph", "/body/DocFragment[2].0"),
        ("/body/DocFragment[2]/body/div/p[4]", "Emoji", "/body/DocFragment[2]/body/div/p[4].0"),
    ])
    func readsAndWritesKOReadersPlaces(place: String, startsWith expected: String, sendsBack: String) async throws {
        let model = try await open()

        let found = try #require(try await resolve(place, in: model), "\(place) didn't resolve")
        let cfi = try #require(found["cfi"] as? String)
        let shown = try await words(at: cfi, in: model)
        #expect(shown.hasPrefix(expected), "\(place) → \(shown)")
        let fraction = try #require(found["fraction"] as? Double)
        #expect((0...1).contains(fraction))
        #expect(found["chapter"] as? String == "Two")
        let back = try await xpointer(at: cfi, in: model)
        #expect(back == sendsBack)
    }

    /// Never a guess: KOReader would open each of these at page 1.
    @Test(arguments: [
        "", "epubcfi(/6/4!/4/2/2/6/1:0)",
        // What Kavita stored after it was sent a CFI.
        "/body/DocFragment[1]/body/epubcfi(/6/14!/4/2/2/6/1:0).0",
        "/body/DocFragment[0].0", "/body/DocFragment[9].0",
        "/body/DocFragment[2]/body/div/p[40].0", "/body/DocFragment[2]/body/section/p.0",
        "/body/DocFragment[2]/body/div/p[1]/../../p.0",
        "/body/DocFragment[2]/body/div/p" + String(repeating: "/p", count: 1100) + ".0",
    ])
    func refusesAPlaceItCantFind(place: String) async throws {
        let model = try await open()

        let found = try await resolve(place, in: model)
        #expect(found == nil)
    }

    @Test func refusesAPlaceThatIsntText() async throws {
        let model = try await open()

        let found = try await resolve(42, in: model)
        #expect(found == nil)
    }

    @Test func relocationsCarryKOReadersPlaceWhenItsWanted() async throws {
        let model = try await open(sync: KOReaderBackend())

        #expect(model.relocation?.xpointer == "/body/DocFragment[1]/body/h1.0")
        #expect(model.position?.xpointer == "/body/DocFragment[1]/body/h1.0")
    }

    @Test func andOnlyThen() async throws {
        let model = try await open()

        #expect(model.relocation?.xpointer == nil)
        #expect(model.position?.xpointer == nil)
    }

    /// A place from KOReader has no CFI: the bridge finds it to open there.
    /// The fraction points far past it, so only the place can show it.
    @Test func opensAtKOReadersPlace() async throws {
        let remote = ReadingPosition(fraction: 0.9, xpointer: "/body/DocFragment[2]/body/div/p[4]/text().13")
        let model = try start(sync: KOReaderBackend(remote: SyncedPosition(position: remote)))

        #expect(await eventually(timeout: .seconds(30)) { model.relocation?.sectionIndex == 1 })
        let shown = await shownText(model)
        #expect(shown.contains("foxtrot golf."), "\(shown.prefix(200))")
    }
}

extension ReaderXPointerTests {
    /// What `opensAtKOReadersPlace` rests on: that fraction alone shows other words.
    @Test func theFractionAloneOpensElsewhere() async throws {
        let model = try start(sync: KOReaderBackend(remote: SyncedPosition(position: ReadingPosition(fraction: 0.9))))

        #expect(await eventually(timeout: .seconds(30)) { model.relocation?.sectionIndex == 1 })
        let shown = await shownText(model)
        #expect(!shown.isEmpty && !shown.contains("foxtrot golf."), "\(shown.prefix(200))")
    }

    /// The page's words, once it has some: a page that has only just moved
    /// may not have been laid out yet.
    private func shownText(_ model: ReaderModel) async -> String {
        var shown = ""
        _ = await eventuallyAwaiting(timeout: .seconds(10)) {
            shown = (try? await model.page.callJavaScript("return await window.octavo.visibleText(2000)") as? String) ?? ""
            return !shown.isEmpty
        }
        return shown
    }
}

/// The reader with a KOReader place it hasn't seen: offered, not followed
/// or overwritten, and taken when you go there.
@MainActor
@Suite(.temporaryFiles)
struct ReaderKOReaderPlaceTests {
    private let store = ReadingPositionStore(
        directory: URL.testDirectory.appending(path: "positions-\(UUID().uuidString)", directoryHint: .isDirectory)
    )
    private static let theirs = ReadingPosition(fraction: 0.05, xpointer: "/body/DocFragment[2]/body/div/p[4]/text().13")
    /// Section one's start: where your place is.
    private static let yours = ReadingPosition(cfi: "epubcfi(/6/2!/4/2)", fraction: 0.01, xpointer: "/body/DocFragment[1]/body/h1.0")

    private func open(_ backend: RecordingKOReader, needsPush: Bool = false) async throws -> ReaderModel {
        try store.save(Self.yours, forBook: "places", needsPush: needsPush)
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "places.epub")
        try ReaderXPointerTests.book().write(to: url)
        let model = ReaderModel(book: ReaderBook(fileURL: url, id: "places"), store: store, sync: backend, pushDelay: .milliseconds(50))
        // Opening by a CFI waits for frames, which a page off screen never
        // draws, so "opened" is sent here once the page has stopped moving,
        // as the bridge sends it once its layout settles.
        #expect(await eventually(timeout: .seconds(30)) { model.relocation != nil })
        _ = try await model.page.callJavaScript("window.requestAnimationFrame = f => setTimeout(f, 16)")
        await settled(model)
        model.handle(.opened(.init(restoredFrom: "cfi", sectionCount: 2, isFixedLayout: false)))
        return model
    }

    /// Until no relocation has come for a second and a half: on a busy Mac
    /// the first layout goes on moving for a while.
    private func settled(_ model: ReaderModel) async {
        var count = model.relocationCount
        var quiet = 0
        for _ in 0..<60 where quiet < 3 {
            try? await Task.sleep(for: .milliseconds(500))
            quiet = model.relocationCount == count ? quiet + 1 : 0
            count = model.relocationCount
        }
    }

    @Test func itsOfferedAndTheBookStaysAtYourPlace() async throws {
        let backend = RecordingKOReader(remote: SyncedPosition(position: Self.theirs, origin: .elsewhere(.first)))
        let model = try await open(backend)

        #expect(await eventually(timeout: .seconds(30)) { model.serverPlace != nil })
        #expect(model.relocation?.sectionIndex == 0)
        let place = try #require(model.serverPlace)
        #expect(place.source == "KOReader")
        #expect(place.chapter == "Two")
        #expect(place.cfi?.hasPrefix("epubcfi(/6/4!") == true)
        #expect(place.label(server: place.source ?? "") == "KOReader: \(ReaderPlace(chapter: nil, location: nil, fraction: place.fraction).percent)")
    }

    @Test func goingThereTakesIt() async throws {
        let remote = SyncedPosition(position: Self.theirs, origin: .elsewhere(.first))
        let backend = RecordingKOReader(remote: remote)
        let model = try await open(backend)
        #expect(await eventually(timeout: .seconds(30)) { model.serverPlace != nil })

        model.goToServerPlace()

        #expect(await eventually(timeout: .seconds(10)) { model.relocation?.sectionIndex == 1 })
        #expect(await eventuallyAwaiting { await backend.adopted == [remote] })
        try await Task.sleep(for: .milliseconds(300))
        let pushes = await backend.pushes
        #expect(pushes.isEmpty, "\(pushes) relocations: \(model.relocationCount)")
    }

    /// Another reader moved on: the book opens there, and that's your place.
    @Test func aMoveAheadIsFollowedAndTaken() async throws {
        let remote = SyncedPosition(position: Self.theirs, origin: .elsewhere(.moved))
        let backend = RecordingKOReader(remote: remote)
        try store.save(Self.yours, forBook: "places")
        let directory = URL.testDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "places.epub")
        try ReaderXPointerTests.book().write(to: url)
        let model = ReaderModel(book: ReaderBook(fileURL: url, id: "places"), store: store, sync: backend, pushDelay: .milliseconds(50))

        #expect(await eventually(timeout: .seconds(30)) { model.relocation?.sectionIndex == 1 })
        model.handle(.opened(.init(restoredFrom: "cfi", sectionCount: 2, isFixedLayout: false)))
        #expect(await eventuallyAwaiting { await backend.adopted == [remote] })
        #expect(model.serverPlace == nil)
    }

    @Test func anUnsentPlaceWaitsForIt() async throws {
        let backend = RecordingKOReader(remote: SyncedPosition(position: Self.theirs, origin: .elsewhere(.moved)))
        let model = try await open(backend, needsPush: true)

        #expect(await eventually(timeout: .seconds(30)) { model.serverPlace != nil })
        try await Task.sleep(for: .milliseconds(300))
        #expect(await backend.pushes.isEmpty)
        #expect(store.progress(forBook: "places")?.needsPush == true)
    }

    @Test func aPlaceItHasSeenIsntOffered() async throws {
        let backend = RecordingKOReader(remote: SyncedPosition(position: Self.theirs, origin: .elsewhere(.unchanged)))
        let model = try await open(backend)

        try await Task.sleep(for: .seconds(1))
        #expect(model.serverPlace == nil)
        #expect(model.relocation?.sectionIndex == 0)
    }
}

/// A KOReader backend that records what the reader does.
private actor RecordingKOReader: ProgressSync {
    let remote: SyncedPosition?
    private(set) var pushes: [ReadingPosition] = []
    private(set) var adopted: [SyncedPosition] = []

    init(remote: SyncedPosition?) {
        self.remote = remote
    }

    func pull() async throws -> SyncedPosition? { remote }
    func push(_ position: ReadingPosition) async throws { pushes.append(position) }
    func adopted(_ remote: SyncedPosition) async { adopted.append(remote) }
    nonisolated var wantsXPointers: Bool { true }
}

/// A KOReader backend as the reader sees it: it wants KOReader's places.
private struct KOReaderBackend: ProgressSync {
    var remote: SyncedPosition?

    func pull() async throws -> SyncedPosition? { remote }
    func push(_ position: ReadingPosition) async throws {}
    var wantsXPointers: Bool { true }
}
