import Foundation

/// Reading settings, kept in `UserDefaults` and shared by every book
/// (decision 14). The Customize panel's toggles (#18) bind to these keys.
nonisolated enum ReaderSettings {
    /// "Book-mode shadow" (decision 9): the shadow in the spine while the
    /// reader is half open like a book.
    static let bookModeShadowKey = "reader.bookModeShadow"
    static let bookModeShadowDefault = true
    /// "Always show controls" (decision 7): the column's buttons stay up
    /// while reading; a middle tap still shows and hides the progress bar.
    /// Off by default.
    static let alwaysShowControlsKey = "reader.alwaysShowControls"
    static let alwaysShowControlsDefault = false
    /// "Margins" (decision 8): `ReaderMargins.key`.
}
