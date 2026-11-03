import Foundation
@testable import OctavoKit
import Testing

/// Formats by their bytes, and the files refused before anything parses
/// them (step 15, `docs/notes/formats-check.md`).
struct BookFileCheckTests {
    // MARK: ZIP

    @Test func anEPUBHasItsContainer() throws {
        let zip = TinyZip.make([("mimetype", "application/epub+zip"), ("META-INF/container.xml", "<container/>"), ("OEBPS/a.xhtml", "<html/>")])
        #expect(try check(zip, name: "book.zip") == .epub)
    }

    @Test func theNameDoesNotMatter() throws {
        let zip = TinyZip.make([("META-INF/container.xml", "<container/>")])
        #expect(try check(zip, name: "book.fb2") == .epub)
    }

    @Test func storeDRMIsRefused() throws {
        for drm in ["META-INF/rights.xml", "META-INF/sinf.xml", "META-INF/license.lcpl"] {
            let zip = TinyZip.make([("META-INF/container.xml", "<container/>"), (drm, "x")])
            #expect(throws: BookFileRefusal.drmProtected) { try check(zip) }
        }
    }

    @Test func fontObfuscationAloneIsFine() throws {
        let zip = TinyZip.make([("META-INF/container.xml", "<container/>"), ("META-INF/encryption.xml", "<encryption/>")])
        #expect(try check(zip) == .epub)
    }

    @Test func aZippedFB2() throws {
        #expect(try check(TinyZip.make([("book.fb2", "<FictionBook/>")])) == .fbz)
    }

    @Test func aComicIsOnlyPictures() throws {
        let zip = TinyZip.make([("01.jpg", "x"), ("02.PNG", "x"), ("ComicInfo.xml", "<x/>"), ("pages/", "")])
        #expect(try check(zip) == .cbz)
    }

    @Test func otherZipsAreNotBooks() {
        #expect(throws: BookFileRefusal.notABook) { try check(TinyZip.make([("notes.txt", "x"), ("a.jpg", "x"), ("b.docx", "x")])) }
        #expect(throws: BookFileRefusal.notABook) { try check(TinyZip.make([("mimetype", "application/epub+zip")])) }
    }

    @Test func zip64IsFollowed() throws {
        let zip = TinyZip.make([("META-INF/container.xml", "<container/>")], zip64: true)
        #expect(try check(zip) == .epub)
    }

    @Test func aBrokenZipIsNotABook() {
        // The signature, then nothing: no end record.
        #expect(throws: BookFileRefusal.notABook) { try check(Data("PK\u{03}\u{04}garbage".utf8)) }
        // An end record pointing past the file.
        var zip = TinyZip.make([("META-INF/container.xml", "<container/>")])
        zip.replaceSubrange(zip.count - 6..<zip.count - 2, with: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: BookFileRefusal.notABook) { try check(zip) }
    }

    // MARK: Kindle

    @Test func mobiAndKF8ByTheirHeader() throws {
        #expect(try check(Kindle.make(version: 6)) == .mobi)
        #expect(try check(Kindle.make(version: 8)) == .azw3)
    }

    @Test func kindleDRMIsRefused() {
        for encryption: UInt16 in [1, 2] {
            #expect(throws: BookFileRefusal.drmProtected) { try check(Kindle.make(version: 8, encryption: encryption)) }
        }
    }

    @Test func aKindleFileWithoutItsRecordIsNotABook() {
        #expect(throws: BookFileRefusal.notABook) { try check(Kindle.make(version: 6).prefix(90)) }
        #expect(throws: BookFileRefusal.notABook) { try check(Kindle.make(version: 6, mobiHeader: false)) }
    }

    @Test func otherKindleFormatsAreUnsupported() {
        var palm = Kindle.make(version: 6)
        palm.replaceSubrange(60..<68, with: Data("TEXtREAd".utf8))
        #expect(throws: BookFileRefusal.unsupported(kind: "PalmDOC")) { try check(palm) }
        #expect(throws: BookFileRefusal.unsupported(kind: "Topaz")) { try check(Data("TPZ0".utf8) + Data(count: 100)) }
        #expect(throws: BookFileRefusal.unsupported(kind: "KFX")) { try check(Data("CONT\u{02}\u{00}".utf8) + Data(count: 100)) }
        #expect(throws: BookFileRefusal.drmProtected) { try check(Data([0xEA]) + Data("DRMION".utf8) + Data([0xEE]) + Data(count: 100)) }
    }

    // MARK: FB2

    @Test func fb2ByItsRoot() throws {
        let fb2 = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n<!-- made by hand -->\n" + #"<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><body/></FictionBook>"#
        #expect(try check(Data(fb2.utf8)) == .fb2)
        #expect(try check(Data([0xEF, 0xBB, 0xBF]) + Data("  <fb:FictionBook xmlns:fb=\"x\"/>".utf8)) == .fb2)
        let utf16 = "\u{FEFF}<?xml version=\"1.0\" encoding=\"UTF-16\"?><FictionBook/>".data(using: .utf16LittleEndian)!
        #expect(try check(utf16) == .fb2)
    }

    @Test func otherXMLIsNotABook() {
        #expect(throws: BookFileRefusal.notABook) { try check(Data("<?xml version=\"1.0\"?><html><body>FictionBook</body></html>".utf8)) }
        #expect(throws: BookFileRefusal.notABook) { try check(Data("FictionBook".utf8)) }
    }

    // MARK: Others

    @Test func otherBooksAreUnsupported() {
        #expect(throws: BookFileRefusal.unsupported(kind: "PDF")) { try check(Data("%PDF-1.7\n".utf8)) }
        #expect(throws: BookFileRefusal.unsupported(kind: "CBR")) { try check(Data("Rar!\u{1A}\u{07}\u{00}".utf8)) }
    }

    @Test func nothingIsNotABook() {
        #expect(throws: BookFileRefusal.notABook) { try check(Data()) }
        #expect(throws: BookFileRefusal.notABook) { try check(Data("Hello".utf8)) }
    }

    @Test func aMissingFileIsTheFileSystemsError() {
        #expect(throws: (any Error).self) { try BookFileCheck.check(URL(filePath: "/nonexistent/\(UUID()).epub")) }
    }

    private func check(_ data: Data, name: String = "book") throws -> BookFileFormat {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID())-\(name)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try BookFileCheck.check(url)
    }
}

/// A minimal ZIP: stored entries, a central directory and its end record,
/// optionally through ZIP64's.
enum TinyZip {
    static func make(_ entries: [(String, String)], zip64: Bool = false) -> Data {
        var data = Data()
        var directory = Data()
        for (name, content) in entries {
            let offset = UInt32(data.count)
            let bytes = Data(content.utf8)
            let crc = crc32(bytes)
            data += le32(0x0403_4B50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
            data += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            data += le16(UInt16(name.utf8.count)) + le16(0) + Data(name.utf8) + bytes
            directory += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
            directory += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            directory += le16(UInt16(name.utf8.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset)
            directory += Data(name.utf8)
        }
        let directoryOffset = UInt32(data.count)
        data += directory
        if zip64 {
            let record = UInt64(data.count)
            data += le32(0x0606_4B50) + le64(44) + le16(45) + le16(45) + le32(0) + le32(0)
            data += le64(UInt64(entries.count)) + le64(UInt64(entries.count)) + le64(UInt64(directory.count)) + le64(UInt64(directoryOffset))
            data += le32(0x0706_4B50) + le32(0) + le64(record) + le32(1)
            data += le32(0x0605_4B50) + le16(0) + le16(0) + le16(0xFFFF) + le16(0xFFFF) + le32(0xFFFF_FFFF) + le32(0xFFFF_FFFF) + le16(0)
        } else {
            data += le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
            data += le32(UInt32(directory.count)) + le32(directoryOffset) + le16(0)
        }
        return data
    }

    static func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    static func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    static func le64(_ value: UInt64) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

/// A minimal PalmDB Kindle file: the 78-byte header, one record, and
/// record 0's PalmDOC and MOBI headers.
enum Kindle {
    static func make(version: UInt32, encryption: UInt16 = 0, mobiHeader: Bool = true) -> Data {
        var data = Data(count: 60) + Data("BOOKMOBI".utf8) + Data(count: 8)
        data += be16(1) + be32(88) + Data(count: 6)
        data += be16(1) + be16(0) + be32(1000) + be16(1) + be16(4096) + be16(encryption) + be16(0)
        data += mobiHeader ? Data("MOBI".utf8) : Data("XXXX".utf8)
        data += be32(232) + be32(2) + be32(65001) + be32(1) + be32(version) + Data(count: 200)
        return data
    }

    static func be16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    static func be32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
}
