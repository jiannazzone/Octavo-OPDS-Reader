import CryptoKit
import Foundation
import ImageIO
import OctavoKit
import UniformTypeIdentifiers

/// A file that didn't come in, and why, for the banner on On iPhone or the
/// line under setup's choices (`docs/design/direction.md`, Other ways in).
nonisolated struct ImportFailure: Error, Hashable, Sendable {
    enum Reason: Hashable, Sendable {
        /// A Kindle file with DRM, which foliate would open as garbage.
        case drmProtected
        /// Not EPUB, MOBI, AZW3 or FB2 (a PDF, KFX, a comic, anything else).
        case notABook
        /// It says it's a book but doesn't open, or couldn't be read.
        case damaged
    }

    var fileName: String
    var reason: Reason

    /// "“Kindred.azw3” is protected with DRM, which Octavo can’t open."
    var message: String {
        switch reason {
        case .drmProtected: "“\(fileName)” is protected with DRM, which Octavo can’t open."
        case .notABook: "“\(fileName)” isn’t a book Octavo reads."
        case .damaged: "“\(fileName)” couldn’t be opened; the file may be damaged."
        }
    }

    /// One line for several: "2 files weren’t imported. …"
    static func summary(_ failures: [ImportFailure]) -> String? {
        guard !failures.isEmpty else { return nil }
        let messages = failures.map(\.message).joined(separator: " ")
        return failures.count == 1 ? messages : "\(failures.count) files weren’t imported. \(messages)"
    }
}

/// Copies a book in from Files (the picker, or Open in Octavo), checks it
/// and reads its details, then keeps it in `ImportedBooks`. The original is
/// left where it was.
///
/// Every file is treated as hostile: it's sniffed by its bytes before
/// anything parses it (`BookFileCheck`), and its details come from foliate
/// under the reader's own script blocking (`BookInspector`).
struct BookImporter {
    let store: ImportedBooks
    /// The file's details, read the way the reader reads it.
    var inspect: (URL) async throws -> BookFileDetails = { try await BookInspector().inspect($0) }
    var now: () -> Date = Date.init

    /// What the Files picker offers: EPUB, and whatever type iOS gives
    /// MOBI, AZW3 and FB2 files (ours from Info.plist, unless another app
    /// declared one first). Anything else is greyed out; what's picked is
    /// still checked by its bytes.
    static var contentTypes: [UTType] {
        [.epub] + ["mobi", "azw", "azw3", "fb2", "fbz"].compactMap { UTType(filenameExtension: $0) }
    }

    /// Formats v1 imports (decision: v1 scope). Comics come later.
    nonisolated static let formats: Set<BookFileFormat> = [.epub, .mobi, .azw3, .fb2, .fbz]

    /// Far beyond any book (the largest illustrated samples are 70 MB), so
    /// a stray huge file isn't copied into the backed-up folder.
    nonisolated static let largestFile: Int64 = 1 << 30

    /// The book `url` holds, now on the iPhone: a new one first in the
    /// list, or the same book imported before, moved first.
    func importFile(at url: URL) async -> Result<LibraryBook, ImportFailure> {
        let name = url.lastPathComponent
        let incoming: Incoming
        do {
            incoming = try await Self.copyIn(url, to: store.incomingDirectory())
        } catch let reason as ImportFailure.Reason {
            return .failure(ImportFailure(fileName: name, reason: reason))
        } catch {
            return .failure(ImportFailure(fileName: name, reason: .damaged))
        }
        let id = LibraryBookID.imported(sha256: incoming.digest)
        if let known = store.details(for: id), known.book.primaryFile.flatMap(store.localFile(for:)) != nil {
            try? FileManager.default.removeItem(at: incoming.url)
            try? store.moveFirst(id)
            return .success(known.book)
        }
        do {
            var details = Self.cleaned(try await inspect(incoming.url))
            // The copy's own format, as the inspector found it: a file
            // swapped after the first check can't sneak in as a comic.
            guard Self.formats.contains(details.format) else { throw ImportFailure.Reason.notABook }
            if let cover = details.cover { details.cover = await Self.coverImage(cover) }
            let book = Self.book(id: id, details: details, fileName: name, size: incoming.size)
            try store.add(
                LibraryBookDetails(
                    book: book, subtitle: details.subtitle, description: details.description,
                    publisher: details.publisher, language: details.language, published: details.published,
                    addedAt: now()
                ),
                file: incoming.url, cover: details.cover
            )
            return .success(book)
        } catch {
            try? FileManager.default.removeItem(at: incoming.url)
            return .failure(ImportFailure(fileName: name, reason: Self.reason(error)))
        }
    }

    static func book(id: LibraryBookID, details: BookFileDetails, fileName: String, size: Int64) -> LibraryBook {
        let fileName = ImportText.line(fileName, limit: 255) ?? "Untitled"
        let file = LibraryFile(
            id: LibraryFileID(rawValue: id.rawValue), format: details.format.fileExtension,
            sizeBytes: Int(size), filename: fileName, isPrimary: true
        )
        return LibraryBook(
            id: id, title: details.title ?? title(fromFileName: fileName), authors: details.authors,
            cover: details.cover == nil ? nil : LibraryCover(rawValue: id.rawValue), files: [file]
        )
    }

    /// A book without a title in its file goes by the file's name:
    /// "Kindred.fb2.zip" → "Kindred".
    static func title(fromFileName name: String) -> String {
        var title = name
        let suffixes = [".zip", ".epub", ".mobi", ".azw3", ".azw", ".fb2", ".fbz"]
        while let suffix = suffixes.first(where: { title.lowercased().hasSuffix($0) }) {
            title = String(title.dropLast(suffix.count))
        }
        return title.trimmingCharacters(in: .whitespaces).isEmpty ? name : title
    }

    static func reason(_ error: any Error) -> ImportFailure.Reason {
        switch error {
        case let reason as ImportFailure.Reason: reason
        case BookFileRefusal.drmProtected, BookInspectionError.drmProtected: .drmProtected
        case BookFileRefusal.unsupported, BookFileRefusal.notABook, BookInspectionError.unsupported: .notABook
        default: .damaged
        }
    }

    /// The book's own words, made safe to show: one line each (no control
    /// or direction-changing characters, which could make "Remove “…” from
    /// this iPhone?" say something else) and capped, the description kept
    /// as paragraphs.
    static func cleaned(_ details: BookFileDetails) -> BookFileDetails {
        var details = details
        details.title = details.title.flatMap { ImportText.line($0, limit: 300) }
        details.subtitle = details.subtitle.flatMap { ImportText.line($0, limit: 300) }
        details.authors = Array(details.authors.compactMap { ImportText.line($0, limit: 200) }.prefix(20))
        details.publisher = details.publisher.flatMap { ImportText.line($0, limit: 200) }
        details.language = details.language.flatMap { ImportText.line($0, limit: 35) }
        details.published = details.published.flatMap { ImportText.line($0, limit: 40) }
        details.description = details.description.flatMap { ImportText.paragraphs($0, limit: 20_000) }
        return details
    }

    /// The cover as a JPEG of at most 1,600 pixels a side, decoded at that
    /// size: a small file can claim to be 30,000 pixels square, and drawn
    /// whole it would take gigabytes. A cover that won't decode is dropped.
    @concurrent nonisolated static func coverImage(_ data: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 30_000, height <= 30_000
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    struct Incoming {
        var url: URL
        var digest: SHA256.Digest
        var size: Int64
    }

    /// Sniffs `url` where it is, then copies it into `directory` under a
    /// name with its real extension (foliate tells FB2 from EPUB by it) and
    /// hashes the copy. Off the main thread: books run to 70 MB.
    @concurrent nonisolated static func copyIn(_ url: URL, to directory: URL) async throws -> Incoming {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordination: NSError?
        var result: Result<Incoming, any Error> = .failure(ImportFailure.Reason.damaged)
        // Waits for a file in iCloud Drive to download.
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordination) { readable in
            result = Result {
                // A plain file only: not a link (copied as a link, it would
                // point out of the folder), a folder, a pipe or a device.
                let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else { throw ImportFailure.Reason.notABook }
                guard Int64(values.fileSize ?? 0) <= largestFile else { throw ImportFailure.Reason.notABook }
                let format: BookFileFormat
                do {
                    format = try BookFileCheck.check(readable)
                } catch let refusal as BookFileRefusal {
                    throw refusal == .drmProtected ? ImportFailure.Reason.drmProtected : .notABook
                }
                guard formats.contains(format) else { throw ImportFailure.Reason.notABook }
                let copy = directory.appending(path: "\(UUID().uuidString).\(format.fileExtension)", directoryHint: .notDirectory)
                try FileManager.default.copyItem(at: readable, to: copy)
                let (digest, size) = try hash(copy)
                guard size <= largestFile else {
                    try? FileManager.default.removeItem(at: copy)
                    throw ImportFailure.Reason.notABook
                }
                return Incoming(url: copy, digest: digest, size: size)
            }
        }
        if let coordination { throw coordination }
        return try result.get()
    }

    private nonisolated static func hash(_ url: URL) throws -> (SHA256.Digest, Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            size += Int64(chunk.count)
        }
        return (hasher.finalize(), size)
    }
}

extension ImportFailure.Reason: Error {}

/// The bundled sample book (decision 6): Standard Ebooks' Pride and
/// Prejudice (CC0), read straight from the first screen so the reader can
/// be tried before any setup. Reading it copies it into `ImportedBooks`,
/// where it stays under On iPhone until it's removed.
nonisolated enum SampleBook {
    static let fileName = "pride-and-prejudice.epub"

    static var bundledFile: URL? {
        Bundle.main.url(forResource: "pride-and-prejudice", withExtension: "epub")
    }

    static var bundledCover: URL? {
        Bundle.main.url(forResource: "pride-and-prejudice-cover", withExtension: "jpg")
    }

    static var book: LibraryBook {
        LibraryBook(
            id: .sample, title: "Pride and Prejudice", authors: ["Jane Austen"],
            cover: LibraryCover(rawValue: LibraryBookID.sample.rawValue),
            files: [LibraryFile(id: LibraryFileID(rawValue: LibraryBookID.sample.rawValue), format: "epub", filename: fileName, isPrimary: true)]
        )
    }

    /// Where it opens the first time: Chapter I, past the title page and imprint
    /// (Adam, 2026-11-03). Read off the bundled file, which doesn't change.
    static let firstChapter = ReadingPosition(cfi: "epubcfi(/6/6!/4/2[chapter-1]/2)", fraction: 0.0066)

    /// Starts the book at `firstChapter` in `store`, unless it has a place.
    static func startAtFirstChapter(in store: ReadingPositionStore) {
        guard let key = book.primaryFile?.storageKey, store.position(forBook: key) == nil else { return }
        try? store.save(firstChapter, forBook: key, chapter: "I")
    }

    /// The book in `store`, copied from the app's bundle if it isn't there.
    @discardableResult
    static func install(into store: ImportedBooks, now: Date = Date()) throws -> LibraryBook {
        if let installed = store.details(for: .sample), installed.book.primaryFile.flatMap(store.localFile(for:)) != nil {
            return installed.book
        }
        guard let bundled = bundledFile else { throw BookFilesError.unreadableFormat }
        let copy = try store.incomingDirectory().appending(path: fileName, directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: bundled, to: copy)
        var book = book
        let size = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
        book.files[0].sizeBytes = size
        try store.add(
            LibraryBookDetails(
                book: book,
                // The book's own (CC0), as plain text.
                description: "Pride and Prejudice may today be one of Jane Austen’s most enduring novels, having been widely adapted to stage, screen, and other media since its publication in 1813. The novel tells the tale of five unmarried sisters and how their lives change when a wealthy eligible bachelor moves in to their neighborhood.",
                publisher: "Standard Ebooks", language: "en-GB", published: "1813", addedAt: now
            ),
            file: copy, cover: bundledCover.flatMap { try? Data(contentsOf: $0) }
        )
        return book
    }
}

/// Text from a book file, made safe to show and store.
nonisolated enum ImportText {
    /// Control characters, and the ones that change or isolate the text's
    /// direction (an override can make a title read backwards from a point).
    private static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x061C, 0xFEFF: true
        default: false
        }
    }

    /// One line: unsafe characters dropped, every run of whitespace (line
    /// breaks too) one space, trimmed and capped. `nil` if nothing's left.
    static func line(_ text: String, limit: Int) -> String? {
        var result = ""
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            if isUnsafe(scalar) { continue }
            if pendingSpace { result.unicodeScalars.append(" ") }
            pendingSpace = false
            result.unicodeScalars.append(scalar)
        }
        let capped = String(result.prefix(limit))
        return capped.isEmpty ? nil : capped
    }

    /// Paragraphs: each line cleaned as `line` does, blank lines kept as
    /// one, capped.
    static func paragraphs(_ text: String, limit: Int) -> String? {
        let lines = String(text.prefix(limit * 2)).split(separator: "\n", omittingEmptySubsequences: false)
        var kept: [String] = []
        for raw in lines {
            if let line = line(String(raw), limit: limit) {
                kept.append(line)
            } else if kept.last?.isEmpty == false {
                kept.append("")
            }
        }
        while kept.last?.isEmpty == true { kept.removeLast() }
        let joined = String(kept.joined(separator: "\n").prefix(limit))
        return joined.isEmpty ? nil : joined
    }
}
