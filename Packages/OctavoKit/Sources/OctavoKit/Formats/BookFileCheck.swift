import Foundation

/// A book format the reader opens, as a file's own bytes say, whatever its
/// name claims.
public enum BookFileFormat: String, Sendable, Codable, CaseIterable {
    case epub
    /// MOBI 6, or a joint MOBI 6 + KF8 file (foliate reads its KF8 part).
    case mobi
    /// KF8 alone.
    case azw3
    case fb2
    /// A zipped FB2.
    case fbz
    case cbz

    /// The extension to keep the file under: foliate tells CBZ and FB2 from
    /// the rest by name.
    public var fileExtension: String { rawValue }
}

/// Why a file won't open.
public enum BookFileRefusal: Error, Equatable, Sendable {
    /// Locked to a store's own apps (Kindle DRM, Adobe ADEPT, Apple
    /// FairPlay, Readium LCP). foliate would open a DRM-marked MOBI as
    /// scrambled text without an error (`docs/notes/formats-spike.md`).
    case drmProtected
    /// A book, but in a format the reader doesn't open: PDF, CBR, KFX,
    /// Topaz, PalmDOC. `kind` names it, for messages.
    case unsupported(kind: String)
    /// Not any book format this knows.
    case notABook
}

/// Tells a book file's format from its bytes, and refuses the ones the
/// reader can't open, before anything parses them (step 15,
/// `docs/notes/formats-check.md`). Every read is bounded: the file is
/// untrusted, and only its first few kilobytes, a Kindle file's first
/// record and a ZIP file's central directory are looked at.
public enum BookFileCheck {
    /// The format of the file at `url`. Throws `BookFileRefusal`, or the
    /// file system's error if the file can't be read.
    public static func check(_ url: URL) throws -> BookFileFormat {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: headLength) ?? Data()
        return try check(head: Bytes(head), size: size) { offset, count in
            try handle.seek(toOffset: offset)
            return Bytes(try handle.read(upToCount: count) ?? Data())
        }
    }

    /// How much of the start of the file is read for its signature.
    static let headLength = 4096
    /// The most of a ZIP central directory that's read: thousands of
    /// entries' names, far more than any book has.
    static let centralDirectoryLimit = 8 << 20

    static func check(head: Bytes, size: UInt64, read: (UInt64, Int) throws -> Bytes) throws -> BookFileFormat {
        if head.starts(with: "PK\u{03}\u{04}") || head.starts(with: "PK\u{05}\u{06}") {
            return try zipFormat(size: size, read: read)
        }
        if head.matches("BOOKMOBI", at: 60) { return try kindleFormat(head: head, size: size, read: read) }
        if head.matches("TEXtREAd", at: 60) { throw BookFileRefusal.unsupported(kind: "PalmDOC") }
        if head.starts(with: "TPZ") { throw BookFileRefusal.unsupported(kind: "Topaz") }
        // KFX: DRM-wrapped, or a plain container.
        if head.starts(with: "\u{EA}DRMION\u{EE}") { throw BookFileRefusal.drmProtected }
        if head.starts(with: "CONT") { throw BookFileRefusal.unsupported(kind: "KFX") }
        if head.starts(with: "%PDF-") { throw BookFileRefusal.unsupported(kind: "PDF") }
        if head.starts(with: "Rar!\u{1A}\u{07}") { throw BookFileRefusal.unsupported(kind: "CBR") }
        if head.starts(with: "7z\u{BC}\u{AF}\u{27}\u{1C}") { throw BookFileRefusal.unsupported(kind: "CB7") }
        if isFictionBook(head) { return .fb2 }
        throw BookFileRefusal.notABook
    }

    // MARK: Kindle

    /// A PalmDB with type and creator `BOOKMOBI`: record 0 holds the
    /// PalmDOC header, whose encryption field (offset 12) is 0 when the
    /// book has no DRM, then the MOBI header, whose file version (offset
    /// 36) is 8 for KF8 alone.
    private static func kindleFormat(head: Bytes, size: UInt64, read: (UInt64, Int) throws -> Bytes) throws -> BookFileFormat {
        // The record list starts at 78, 8 bytes a record.
        guard (head.be16(at: 76) ?? 0) > 0, let first = head.be32(at: 78), UInt64(first) + 40 <= size else {
            throw BookFileRefusal.notABook
        }
        let record0: Bytes
        if Int(first) + 40 <= head.count {
            record0 = head.slice(Int(first), 40)
        } else {
            record0 = try read(UInt64(first), 40)
        }
        guard record0.count == 40 else { throw BookFileRefusal.notABook }
        guard record0.be16(at: 12) == 0 else { throw BookFileRefusal.drmProtected }
        // PalmDOC text in a BOOKMOBI wrapper has no MOBI header, and foliate
        // reads nothing without one.
        guard record0.matches("MOBI", at: 16) else { throw BookFileRefusal.notABook }
        return record0.be32(at: 36) == 8 ? .azw3 : .mobi
    }

    // MARK: ZIP

    /// EPUB, CBZ or a zipped FB2, from the names in the central directory:
    /// an EPUB has `META-INF/container.xml`, an FBZ an `.fb2` file, a CBZ
    /// only pictures. DRM schemes leave their own files beside the book.
    private static func zipFormat(size: UInt64, read: (UInt64, Int) throws -> Bytes) throws -> BookFileFormat {
        let names = try zipNames(size: size, read: read)
        let lowercased = names.map { $0.lowercased() }
        let set = Set(lowercased)
        if set.contains("meta-inf/container.xml") {
            // Adobe ADEPT, Apple FairPlay, Readium LCP. Font obfuscation
            // alone (`encryption.xml` with nothing else) is fine: foliate
            // undoes it.
            if !set.isDisjoint(with: ["meta-inf/rights.xml", "meta-inf/sinf.xml", "meta-inf/license.lcpl"]) {
                throw BookFileRefusal.drmProtected
            }
            return .epub
        }
        if lowercased.contains(where: { $0.hasSuffix(".fb2") }) { return .fbz }
        let pictures = lowercased.filter { !$0.hasSuffix("/") && !isZipMetadata($0) }
        if !pictures.isEmpty, pictures.allSatisfy(isPicture) { return .cbz }
        // Anything else zipped, an EPUB without its container among them:
        // foliate couldn't find a package to read.
        throw BookFileRefusal.notABook
    }

    private static let pictureExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "avif", "jxl", "bmp", "tif", "tiff"]

    private static func isPicture(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        return pictureExtensions.contains(String(name[name.index(after: dot)...]))
    }

    /// Files a comic archive may carry beside its pages.
    private static func isZipMetadata(_ name: String) -> Bool {
        name.hasPrefix("__macosx/") || name.hasSuffix(".xml") || name.hasSuffix(".txt") || name.hasSuffix(".nfo")
            || name.hasSuffix(".ds_store") || name.hasSuffix("thumbs.db")
    }

    /// The entries' names, from the end-of-central-directory record (in
    /// the last 64 KiB) and the central directory it points at. ZIP64
    /// archives are followed through their locator.
    static func zipNames(size: UInt64, read: (UInt64, Int) throws -> Bytes) throws -> [String] {
        let tailLength = Int(min(size, 22 + 0xFFFF))
        let tail = try read(size - UInt64(tailLength), tailLength)
        guard let end = tail.lastIndex(of: [0x50, 0x4B, 0x05, 0x06]), tail.count - end >= 22 else {
            throw BookFileRefusal.notABook
        }
        var count = UInt64(tail.le16(at: end + 10) ?? 0)
        var length = UInt64(tail.le32(at: end + 12) ?? 0)
        var offset = UInt64(tail.le32(at: end + 16) ?? 0)
        if count == 0xFFFF || length == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
            // ZIP64: the locator sits just before the end record.
            guard end >= 20, tail.matches([0x50, 0x4B, 0x06, 0x07], at: end - 20),
                  let record = tail.le64(at: end - 20 + 8), record <= size, size - record >= 56
            else { throw BookFileRefusal.notABook }
            let zip64 = try read(record, 56)
            guard zip64.matches([0x50, 0x4B, 0x06, 0x06], at: 0),
                  let c = zip64.le64(at: 32), let l = zip64.le64(at: 40), let o = zip64.le64(at: 48)
            else { throw BookFileRefusal.notABook }
            (count, length, offset) = (c, l, o)
        }
        guard length <= UInt64(centralDirectoryLimit), offset <= size, length <= size - offset else {
            throw BookFileRefusal.notABook
        }
        let directory = try read(offset, Int(length))
        var names: [String] = []
        var at = 0
        // 46 bytes of fixed header, then the name, extra field and comment.
        while names.count < count, at + 46 <= directory.count, directory.matches([0x50, 0x4B, 0x01, 0x02], at: at) {
            guard let nameLength = directory.le16(at: at + 28), let extraLength = directory.le16(at: at + 30),
                  let commentLength = directory.le16(at: at + 32)
            else { break }
            let nameStart = at + 46
            guard nameStart + Int(nameLength) <= directory.count else { break }
            let name = directory.slice(nameStart, Int(nameLength))
            names.append(String(decoding: name.data, as: UTF8.self))
            at = nameStart + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }
        guard !names.isEmpty else { throw BookFileRefusal.notABook }
        return names
    }

    // MARK: FB2

    /// An XML document whose root is `FictionBook` (in any namespace
    /// prefix), within the first few kilobytes, as UTF-8 or UTF-16.
    private static func isFictionBook(_ head: Bytes) -> Bool {
        let text: String
        if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) {
            text = String(data: head.data, encoding: .utf16) ?? ""
        } else {
            text = String(decoding: head.data, as: UTF8.self)
        }
        let trimmed = text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
        guard trimmed.hasPrefix("<") else { return false }
        // The root element: the first `<` that starts a name, after any
        // declaration, comments and doctype.
        var rest = trimmed[...]
        while let open = rest.firstIndex(of: "<") {
            let after = rest[rest.index(after: open)...]
            if after.hasPrefix("?") || after.hasPrefix("!") {
                // A doctype's internal subset holds `>`s of its own.
                let end = after.hasPrefix("!DOCTYPE") && after.prefix { $0 != ">" }.contains("[") ? "]>" : ">"
                guard let close = after.range(of: end) else { return false }
                rest = after[close.upperBound...]
                continue
            }
            let name = after.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
            return name == "FictionBook" || name.hasSuffix(":FictionBook")
        }
        return false
    }
}

/// A few bytes of an untrusted file, read with bounds checks.
struct Bytes {
    let data: Data

    init(_ data: Data) {
        // Indices from 0, whatever `data` was sliced from.
        self.data = Data(data)
    }

    var count: Int { data.count }

    func starts(with prefix: String) -> Bool {
        matches(Array(prefix.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }), at: 0)
    }

    func starts(with prefix: [UInt8]) -> Bool {
        matches(prefix, at: 0)
    }

    func matches(_ string: String, at offset: Int) -> Bool {
        matches(Array(string.utf8), at: offset)
    }

    func matches(_ bytes: [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + bytes.count <= data.count else { return false }
        return data[offset..<offset + bytes.count].elementsEqual(bytes)
    }

    func slice(_ offset: Int, _ length: Int) -> Bytes {
        guard offset >= 0, length >= 0, offset <= data.count else { return Bytes(Data()) }
        return Bytes(data[offset..<min(data.count, offset + length)])
    }

    /// Big-endian, as PalmDB and MOBI headers are.
    func be16(at offset: Int) -> UInt16? { integer(at: offset, bytes: 2, bigEndian: true).map { UInt16(truncatingIfNeeded: $0) } }
    func be32(at offset: Int) -> UInt32? { integer(at: offset, bytes: 4, bigEndian: true).map { UInt32(truncatingIfNeeded: $0) } }
    /// Little-endian, as ZIP's records are.
    func le16(at offset: Int) -> UInt16? { integer(at: offset, bytes: 2, bigEndian: false).map { UInt16(truncatingIfNeeded: $0) } }
    func le32(at offset: Int) -> UInt32? { integer(at: offset, bytes: 4, bigEndian: false).map { UInt32(truncatingIfNeeded: $0) } }
    func le64(at offset: Int) -> UInt64? { integer(at: offset, bytes: 8, bigEndian: false) }

    private func integer(at offset: Int, bytes: Int, bigEndian: Bool) -> UInt64? {
        guard offset >= 0, offset <= data.count - bytes else { return nil }
        let field = data[offset..<offset + bytes]
        return (bigEndian ? Array(field) : field.reversed()).reduce(0) { $0 << 8 | UInt64($1) }
    }

    func lastIndex(of bytes: [UInt8]) -> Int? {
        guard data.count >= bytes.count else { return nil }
        for start in stride(from: data.count - bytes.count, through: 0, by: -1) where matches(bytes, at: start) {
            return start
        }
        return nil
    }
}
