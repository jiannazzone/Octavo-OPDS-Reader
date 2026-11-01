import Foundation

/// Reading settings, kept in `UserDefaults` and shared by every book
/// (decision 14). The Customize panel's toggles (#18) bind to these keys.
nonisolated enum ReaderSettings {
    /// "Book-mode shadow" (decision 9): the shadow in the spine while the
    /// reader is half open like a book.
    static let bookModeShadowKey = "reader.bookModeShadow"
    static let bookModeShadowDefault = true
}
