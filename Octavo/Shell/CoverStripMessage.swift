import Foundation

/// A debug stand-in for a problem or progress with one book
/// (`-shellCoverStrip`), shown on its screen where Open would be
/// (`BookOpenButton`). Queuing a download for later isn't offered.
nonisolated enum CoverStripMessage: Hashable, Sendable {
    case downloadFailed
    /// Offline, and the book isn't on the iPhone yet.
    case needsConnection
    case downloading(fraction: Double)
    /// Downloaded, and refused for its DRM.
    case protected
}
