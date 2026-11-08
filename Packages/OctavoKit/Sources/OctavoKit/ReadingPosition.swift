/// Where the reader is in a book. The one position model every engine and
/// sync backend converts to and from.
///
/// - `cfi` is the EPUB CFI foliate-js reports. `nil` for formats without one
///   (PDF, comics).
/// - `fraction` is progress through the whole book, 0...1. Backends that use
///   a 0–100 percentage convert at their edge.
/// - `pageNumber` is set for fixed-layout formats (PDF, comics), 1-based.
/// - `xpointer` is KOReader's place for the same spot (an EPUB that syncs
///   with KOReader, `docs/notes/koreader-sync.md`), or a place from KOReader
///   with no CFI yet. A percentage alone can't move KOReader.
public struct ReadingPosition: Codable, Hashable, Sendable {
    public var cfi: String?
    public var fraction: Double
    public var pageNumber: Int?
    public var xpointer: String?

    public init(cfi: String? = nil, fraction: Double, pageNumber: Int? = nil, xpointer: String? = nil) {
        self.cfi = cfi
        self.fraction = fraction
        self.pageNumber = pageNumber
        self.xpointer = xpointer
    }
}
