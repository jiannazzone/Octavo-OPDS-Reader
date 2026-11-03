import Foundation
import OctavoKit
import Testing

/// FB2 covers from the file, since the reader's CSP blocks foliate's own
/// read (`docs/notes/formats-spike.md`).
struct FB2CoverTests {
    private func fb2(cover: String? = ##"<image l:href="#cover.jpg"/>"##, binaries: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description><title-info><book-title>Alice</book-title>\(cover.map { "<coverpage>\($0)</coverpage>" } ?? "")</title-info></description>
        <body><section><p>Text <image l:href="#inline.png"/></p></section></body>
        \(binaries)
        </FictionBook>
        """.utf8)
    }

    @Test func readsTheBinaryTheCoverPageNames() {
        let book = fb2(binaries: """
        <binary id="inline.png" content-type="image/png">AAAA</binary>
        <binary id="cover.jpg" content-type="image/jpeg">
        /9j/
        4AAQ
        </binary>
        """)
        let cover = FB2Cover.read(book)
        #expect(cover?.data == Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]))
        #expect(cover?.mimeType == "image/jpeg")
    }

    @Test func anyPrefixForTheLink() {
        let book = Data(##"<FictionBook xmlns:xlink="http://www.w3.org/1999/xlink"><description><title-info><coverpage><image xlink:href="#c"/></coverpage></title-info></description><binary id="c">AQID</binary></FictionBook>"##.utf8)
        #expect(FB2Cover.read(book)?.data == Data([1, 2, 3]))
        #expect(FB2Cover.read(book)?.mimeType == nil)
    }

    @Test func noCoverPageNoCover() {
        #expect(FB2Cover.read(fb2(cover: nil, binaries: #"<binary id="cover.jpg">AQID</binary>"#)) == nil)
        // Only images in the cover page count, not the book's others.
        #expect(FB2Cover.read(fb2(cover: "", binaries: #"<binary id="inline.png">AQID</binary>"#)) == nil)
    }

    @Test func aRemoteCoverIsNotFetched() {
        #expect(FB2Cover.read(fb2(cover: #"<image l:href="http://localhost:8799/cover"/>"#, binaries: "")) == nil)
    }

    @Test func tooLargeIsNoCover() {
        let book = fb2(binaries: #"<binary id="cover.jpg">"# + String(repeating: "AAAA", count: 1000) + "</binary>")
        #expect(FB2Cover.read(book, limit: 1000) == nil)
        #expect(FB2Cover.read(book, limit: 4000)?.data.count == 3000)
    }

    @Test func externalEntitiesAreNotRead() {
        let book = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE FictionBook [ <!ENTITY hosts SYSTEM "file:///etc/hosts"> ]>
        <FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><coverpage><image l:href="#c"/></coverpage></title-info></description><binary id="c">AQID&hosts;</binary></FictionBook>
        """.utf8)
        // Without the file's text, the binary is the three bytes or nothing.
        let cover = FB2Cover.read(book)
        #expect(cover == nil || cover?.data == Data([1, 2, 3]))
    }

    @Test func readsFromAFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).fb2")
        try fb2(binaries: #"<binary id="cover.jpg" content-type="image/jpeg">AQID</binary>"#).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FB2Cover.read(from: url)?.data == Data([1, 2, 3]))
    }
}
