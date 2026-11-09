import SwiftUI
import UIKit

/// Where the screens show a book's cover, in the window, for the book
/// opening and closing like a cover (`ReaderCoverMotion`): a book's own
/// screen (`BookCoverArt`). Each cover reports here as it lays out and as it
/// appears, and takes its report away when it goes; the shell asks for the
/// one under the reader. Not observed: nothing draws from it.
@MainActor
final class CoverSpots {
    /// The screen a cover is on: each book's screen keeps its own.
    enum Screen: Hashable {
        case book(SourcedBook.ID)
    }

    private(set) var spots: [Screen: CoverSpot] = [:]
    /// The view that reported each. A view going clears only its own: a fold
    /// makes the cover's view again, and Home's page while it loads goes after
    /// the page with your book has reported, so the one going may not be the
    /// last to report.
    private var reporters: [Screen: UUID] = [:]

    /// A cover's view reports whenever it appears, as well as when it moves:
    /// a tab switch takes it away and back without moving it.
    func report(_ spot: CoverSpot, on screen: Screen, from reporter: UUID) {
        spots[screen] = spot
        reporters[screen] = reporter
    }

    func gone(from screen: Screen, reporter: UUID) {
        guard reporters[screen] == reporter else { return }
        spots[screen] = nil
        reporters[screen] = nil
    }

    /// `book`'s cover on its screen, if that's the one on top.
    func spot(for book: SourcedBook.ID, top: ShellRoute?) -> CoverSpot? {
        guard case .cover(let shown)? = top, shown.id == book else { return nil }
        guard let spot = spots[.book(book)], spot.book == book, !spot.frame.isEmpty else { return nil }
        return spot
    }
}

/// A cover as its screen draws it (`BookCoverArt`), for the cover's motion to
/// start from or land on.
struct CoverSpot: Equatable {
    var book: SourcedBook.ID
    /// In the window's coordinates.
    var frame: CGRect
    /// The picture showing, which outlives the cache; without one, the title.
    var image: UIImage?
    var title: String
    var author: String
    /// On a spread's left page (Cover | Details); else it fills its screen.
    var spread = false
}

extension UIWindow {
    /// The scene's key window: what the cover's motion draws over and takes
    /// pictures of.
    static var key: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }
}
