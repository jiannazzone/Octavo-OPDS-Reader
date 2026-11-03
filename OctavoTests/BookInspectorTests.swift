import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// An imported file's details, through foliate in a page that's never
/// shown, and the files refused before that (step 15,
/// `docs/notes/formats-check.md`).
@MainActor
@Suite(.temporaryFiles)
struct BookInspectorTests {
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func file(_ data: Data, _ name: String) throws -> URL {
        let directory = URL.testDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url)
        return url
    }

    static func epub(opf metadata: String, spine: Bool = true, extra: [(String, Data)] = []) -> Data {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">urn:uuid:7b0c5b2e-0000-4000-8000-000000000001</dc:identifier>
        \(metadata)
        <meta property="dcterms:modified">2026-11-02T00:00:00Z</meta>
        </metadata>
        <manifest>
        <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine>\(spine ? #"<itemref idref="c1"/>"# : "")</spine>
        </package>
        """
        let page = #"<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>One</title></head><body><p>It is a truth universally acknowledged.</p><script>top.__bookScriptRan = true</script></body></html>"#
        let nav = #"<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="c1.xhtml">One</a></li></ol></nav></body></html>"#
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        return StoredZip.make([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/nav.xhtml", Data(nav.utf8)),
            ("OEBPS/c1.xhtml", Data(page.utf8)),
            ("OEBPS/cover.png", png),
        ] + extra)
    }

    private static func encryption(_ algorithm: String) -> (String, Data) {
        ("META-INF/encryption.xml", Data("""
        <?xml version="1.0"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:EncryptionMethod Algorithm="\(algorithm)"/><enc:CipherData><enc:CipherReference URI="OEBPS/c1.xhtml"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """.utf8))
    }

    @Test func encryptedContentIsDRM() async throws {
        // Kobo's DRM: AES on the text, and no file of its own beside it.
        let locked = try file(Self.epub(opf: "<dc:title>Locked</dc:title>", extra: [Self.encryption("http://www.w3.org/2001/04/xmlenc#aes128-cbc")]), "locked.epub")
        await #expect(throws: BookInspectionError.drmProtected) { try await BookInspector().inspect(locked) }
        // Obfuscated fonts alone are fine.
        let fonts = try file(Self.epub(opf: "<dc:title>Fonts</dc:title>", extra: [Self.encryption("http://www.idpf.org/2008/embedding")]), "fonts.epub")
        #expect(try await BookInspector().inspect(fonts).title == "Fonts")
    }

    @Test func readsAnEPUBsDetailsAndCover() async throws {
        let url = try file(Self.epub(opf: """
        <dc:title>Pride and Prejudice</dc:title>
        <dc:creator>Jane Austen</dc:creator>
        <dc:creator>R. W. Chapman</dc:creator>
        <dc:language>en-GB</dc:language>
        <dc:date>1813-01-28</dc:date>
        <dc:publisher>Octavo Tests</dc:publisher>
        <dc:description>&lt;p&gt;It is a truth &lt;i&gt;universally&lt;/i&gt; acknowledged.&lt;/p&gt;&lt;script&gt;alert(1)&lt;/script&gt;</dc:description>
        """), "Some download (1).zip")
        let details = try await BookInspector().inspect(url)
        #expect(details.format == .epub)
        #expect(details.title == "Pride and Prejudice")
        #expect(details.authors == ["Jane Austen", "R. W. Chapman"])
        #expect(details.language == "en-GB")
        #expect(details.published == "1813-01-28")
        #expect(details.publisher == "Octavo Tests")
        #expect(details.description == "It is a truth universally acknowledged.")
        #expect(details.cover == Self.png)
    }

    @Test func aBookWithoutDetailsHasNone() async throws {
        let url = try file(Self.epub(opf: "<dc:title></dc:title>"), "untitled.epub")
        let details = try await BookInspector().inspect(url)
        #expect(details.title == nil)
        #expect(details.authors.isEmpty)
        #expect(details.description == nil)
    }

    @Test func anFB2WithItsCoverFromTheFile() async throws {
        let fb2 = ##"""
        <?xml version="1.0" encoding="UTF-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description><title-info>
        <author><first-name>Lewis</first-name><last-name>Carroll</last-name></author>
        <book-title>Alice’s Adventures in Wonderland</book-title>
        <annotation><p>Down the <emphasis>rabbit</emphasis>-hole.</p></annotation>
        <lang>en</lang>
        <coverpage><image l:href="#cover.png"/></coverpage>
        </title-info></description>
        <body><section><title><p>Chapter I</p></title><p>Alice was beginning to get very tired.</p></section></body>
        <binary id="cover.png" content-type="image/png">iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==</binary>
        </FictionBook>
        """##
        let details = try await BookInspector().inspect(try file(Data(fb2.utf8), "alice.xml"))
        #expect(details.format == .fb2)
        #expect(details.title == "Alice’s Adventures in Wonderland")
        #expect(details.authors == ["Lewis Carroll"])
        #expect(details.language == "en")
        #expect(details.description == "Down the rabbit-hole.")
        #expect(details.cover == Self.png)
    }

    @Test func drmIsRefusedBeforeReading() async throws {
        // A Kindle file whose record 0 says Mobipocket DRM.
        var data = Data(count: 60) + Data("BOOKMOBI".utf8) + Data(count: 8)
        data += Data([0, 1, 0, 0, 0, 88]) + Data(count: 6)
        data += Data([0, 2, 0, 0, 0, 0, 3, 232, 0, 1, 16, 0, 0, 2, 0, 0]) + Data("MOBI".utf8) + Data(count: 300)
        await #expect(throws: BookInspectionError.drmProtected) { try await BookInspector().inspect(try file(data, "book.azw")) }
    }

    @Test func otherFormatsAreUnsupported() async throws {
        await #expect(throws: BookInspectionError.unsupported(kind: "PDF")) {
            try await BookInspector().inspect(try file(Data("%PDF-1.7\n%…".utf8), "book.pdf"))
        }
        await #expect(throws: BookInspectionError.unsupported(kind: nil)) {
            try await BookInspector().inspect(try file(Data("Just some notes.".utf8), "notes.epub"))
        }
    }

    @Test func anEPUBThatWontOpenIsDamaged() async throws {
        // Its container names a package that isn't there.
        let container = #"<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/missing.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"#
        let broken = StoredZip.make([("mimetype", Data("application/epub+zip".utf8)), ("META-INF/container.xml", Data(container.utf8))])
        await #expect(throws: BookInspectionError.damaged) { try await BookInspector().inspect(try file(broken, "broken.epub")) }
        // Nothing to read.
        let empty = try file(Self.epub(opf: "<dc:title>Empty</dc:title>", spine: false), "empty.epub")
        await #expect(throws: BookInspectionError.damaged) { try await BookInspector().inspect(empty) }
    }

    @Test func aSlowReadTimesOut() async throws {
        let url = try file(Self.epub(opf: "<dc:title>Slow</dc:title>"), "slow.epub")
        await #expect(throws: BookInspectionError.damaged) { try await BookInspector(timeout: .milliseconds(1)).inspect(url) }
    }

    @Test func aPageThatNeverAnswersIsDropped() async throws {
        // A book that keeps foliate busy for good: the answer never comes,
        // and the timeout gives up on it, with nothing left waiting on the
        // page (`HiddenReader`).
        let url = try file(Self.epub(opf: "<dc:title>Busy</dc:title>"), "busy.epub")
        var inspector = BookInspector(timeout: .seconds(2))
        inspector.script = "setTimeout(() => { for (;;) {} }, 0)"
        let started = ContinuousClock.now
        await #expect(throws: BookInspectionError.damaged) { try await inspector.inspect(url) }
        #expect(ContinuousClock.now - started < .seconds(10))
        // A busy page left behind wouldn't stop the next one.
        #expect(try await BookInspector().inspect(url).title == "Busy")
    }

    @Test func aLongDescriptionIsCut() {
        let markup = String(repeating: "<p>Call me Ishmael.</p>", count: 50_000)
        let details = BookInspector.details(from: ["title": "Moby-Dick", "description": markup], format: .epub)
        #expect((details.description?.count ?? 0) <= BookInspector.descriptionLimit)
        #expect(details.description?.hasPrefix("Call me Ishmael.") == true)
    }

    @Test func tidiesFoliatesAnswer() {
        let details = BookInspector.details(from: [
            "title": "  Moby-Dick  ", "subtitle": "", "authors": ["Herman Melville", " "],
            "description": "<p>Call me <i>Ishmael</i>.</p>", "cover": ["data": "AQID", "type": NSNull()],
        ], format: .azw3)
        #expect(details == BookFileDetails(format: .azw3, title: "Moby-Dick", authors: ["Herman Melville"], description: "Call me Ishmael.", cover: Data([1, 2, 3])))
    }

    @Test func kindleDatesAreDays() {
        let date = { BookInspector.details(from: ["published": $0], format: .mobi).published }
        #expect(date("2008-06-27T04:00:00+00:00") == "2008-06-27")
        #expect(date("2026-11-02T23:44:52.884589+00:00") == "2026-11-02")
        #expect(date("1813-01-28") == "1813-01-28")
        #expect(date("1813") == "1813")
    }
}

/// A ZIP of stored entries, as an EPUB's `mimetype` must be.
enum StoredZip {
    static func make(_ entries: [(String, Data)]) -> Data {
        var data = Data()
        var directory = Data()
        for (name, bytes) in entries {
            let offset = UInt32(data.count)
            let crc = crc32(bytes)
            let header = le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count)) + le16(UInt16(name.utf8.count))
            data += le32(0x0403_4B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + header + le16(0) + Data(name.utf8) + bytes
            directory += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0) + header
            directory += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + Data(name.utf8)
        }
        let directoryOffset = UInt32(data.count)
        data += directory
        data += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
        data += le32(UInt32(directory.count)) + le32(directoryOffset) + le16(0)
        return data
    }

    private static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
