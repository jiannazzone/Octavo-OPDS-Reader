import Foundation

/// Reading settings, kept in `UserDefaults` and shared by every book
/// (decision 14). The Customize panel's toggles (#18) bind to these keys.
nonisolated enum ReaderSettings {
    /// "Book-mode shadow" (decision 9): the shadow in the spine while the
    /// reader is half open like a book.
    static let bookModeShadowKey = "reader.bookModeShadow"
    static let bookModeShadowDefault = true
    /// "Always show controls" (decision 7): the column's buttons stay up
    /// while reading. Off by default.
    static let alwaysShowControlsKey = "reader.alwaysShowControls"
    static let alwaysShowControlsDefault = false
    /// "Margins" (decision 8): `ReaderMargins.key`.
    /// "Page Turn" (decision 27): `ReaderPageTurn.key`.
    /// "Keep screen on", in Settings: `ReaderScreenOn.key`.
    /// "Close book when folded", in Settings: folding while reading closes the
    /// book back to its screen. Off, the book stays open at your place on the
    /// folded screen. The tour ignores it (`ShellModel.tourHingeChanged`).
    static let closeBookWhenFoldedKey = "reader.closeBookWhenFolded"
    static let closeBookWhenFoldedDefault = true

    static func closesBookWhenFolded(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: closeBookWhenFoldedKey) == nil ? closeBookWhenFoldedDefault : defaults.bool(forKey: closeBookWhenFoldedKey)
    }
}
