import SwiftUI
import UIKit

/// Where the screens show a book's cover, in the window, for the book
/// opening and closing like a cover (`ReaderCoverMotion`): a book's own
/// screen, and Home's left page unfolded. Each screen reports here as it lays
/// out and takes its report away when it goes; the shell asks for the one
/// under the reader. Not observed: nothing draws from it.
@MainActor
final class CoverSpots {
    /// Home's, once it has measured all of it.
    private(set) var home = HomeCoverReport()
    /// The Home page that reported it. A page going clears only its own: the
    /// page Home showed while loading goes after the one with your book has
    /// reported, and cleared it, so Open had no cover to move.
    private var homeReporter: UUID?
    /// Each book's screen's cover, by book: a screen under another keeps its
    /// own.
    var bookScreens: [SourcedBook.ID: CGRect] = [:]

    func reportHome(_ report: HomeCoverReport, from reporter: UUID) {
        home = report
        homeReporter = reporter
    }

    func homeGone(_ reporter: UUID) {
        guard homeReporter == reporter else { return }
        home = HomeCoverReport()
        homeReporter = nil
    }

    /// The cover the book opens from, or closes onto.
    enum Spot: Equatable {
        /// Home's left page (it has the cover, its blur and its strip).
        case home(HomeCoverSpot)
        /// A book's screen: the cover's frame.
        case bookScreen(CGRect)
    }

    /// `book`'s cover on the screen showing: Home's when Home's root is
    /// showing, else the book's screen's if that's on top.
    func spot(for book: SourcedBook.ID, onHome: Bool, top: ShellRoute?) -> Spot? {
        if onHome {
            guard let spot = home.spot, spot.book?.id == book else { return nil }
            return .home(spot)
        }
        guard case .cover(let shown)? = top, shown.id == book,
              let frame = bookScreens[book], !frame.isEmpty
        else { return nil }
        return .bookScreen(frame)
    }
}

/// What Home reports of its cover as each part is measured. Nothing until
/// all of it is: a cover moving with its strip unmeasured would leave the
/// cover's copy showing.
struct HomeCoverReport: Equatable {
    var book: SourcedBook?
    var image: UIImage?
    var cover: CGRect?
    var page: CGRect?
    var stripTop: CGFloat?

    /// The whole spot, once the cover, the page and the strip are measured
    /// (and the strip is on the page, below its top).
    var spot: HomeCoverSpot? {
        guard let book, let cover, let page, let stripTop,
              !cover.isEmpty, !page.isEmpty, stripTop > page.minY
        else { return nil }
        return HomeCoverSpot(book: book, image: image, cover: cover, page: page, stripTop: stripTop)
    }
}

extension UIWindow {
    /// The scene's key window: what the cover's motion draws over and takes
    /// pictures of.
    static var key: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }
}
