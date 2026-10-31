/// Where the reader is in a book. The one position model every engine and
/// sync backend converts to and from.
///
/// - `cfi` is the EPUB CFI foliate-js reports. `nil` for formats without one
///   (PDF, comics).
/// - `fraction` is progress through the whole book, 0...1. Backends that use
///   a 0–100 percentage convert at their edge. Percentage-only backends such
///   as kosync sync from this alone.
/// - `pageNumber` is set for fixed-layout formats (PDF, comics), 1-based.
public struct ReadingPosition: Codable, Hashable, Sendable {
    public var cfi: String?
    public var fraction: Double
    public var pageNumber: Int?

    public init(cfi: String? = nil, fraction: Double, pageNumber: Int? = nil) {
        self.cfi = cfi
        self.fraction = fraction
        self.pageNumber = pageNumber
    }
}
