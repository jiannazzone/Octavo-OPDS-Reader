import OctavoKit
import SwiftUI

/// A book's screen (`docs/design/direction.md`, A book's screen).
///
/// - Folded, the cover fills the screen, running under the side column and
///   the camera, with a glass sheet at the bottom: the title, the place,
///   Download and Open; pulled up, the details. Tapping the cover while the
///   details show returns to the strip.
/// - Unfolded, Cover | Details: the cover fills the left page and the same
///   summary and details sit on the right page.
/// - Nothing is drawn behind the side column: the system's own glass
///   capsules (clock, Back, tabs) read on any cover.
/// - Unfolding on this screen opens the book if it's on the iPhone
///   (`ShellModel.hingeChanged`), at once: the server's place is pulled when
///   the screen appears and when the app comes back to it (`BookPlaces`).
struct BookCoverPage: View {
    let book: LibraryBook
    let sourceID: LibrarySourceID
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell
    @Environment(\.spread) private var spread
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let page = shell.pages.page(for: book)
        // The shelf's cover, until the full-size one loads: the screen
        // slides in with a cover on it, not an empty frame.
        let thumbnail = shell.library.covers.cachedImage(for: SourcedBook(source: sourceID, book: book), size: .thumbnail)
        Group {
            if let pages = spread.pages {
                HStack(spacing: 0) {
                    BookCoverArt(page: page, thumbnail: thumbnail)
                        .frame(width: pages.leftWidth)
                        .ignoresSafeArea(edges: .vertical)
                    Color.clear
                        .frame(width: pages.hingeWidth)
                    BookInfoPage(page: page, source: source, sourceID: sourceID)
                        .frame(width: pages.rightWidth)
                }
            } else {
                ZStack(alignment: .bottom) {
                    BookCoverArt(page: page, thumbnail: thumbnail)
                        .ignoresSafeArea()
                        .onTapGesture {
                            guard page.isExpanded else { return }
                            withAnimation(BookSheet.animation) { page.isExpanded = false }
                        }
                    // 8 pt from the bottom edge, as in frame 03.
                    BookSheet(page: page, source: source, sourceID: sourceID)
                        .padding(8)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            }
        }
        .onAppear {
            page.load(from: source)
            page.keepFinished(in: shell.library.finished, as: SourcedBook.ID(source: sourceID, book: book.id))
            shell.opener.clearFailure(book)
            shell.places.refresh(SourcedBook(source: sourceID, book: book))
        }
        .onChange(of: scenePhase) { _, phase in
            // Not under the reader: its own pushes keep the place current.
            guard phase == .active, shell.reading == nil else { return }
            shell.places.refresh(SourcedBook(source: sourceID, book: book))
        }
    }
}

/// The right page unfolded: what the folded sheet shows, as a page.
struct BookInfoPage: View {
    let page: BookPage
    let source: any LibrarySource
    let sourceID: LibrarySourceID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BookSummary(page: page, source: source, sourceID: sourceID, titleFont: .title2.bold(), titleLines: 4)
                BookDetails(page: page, source: source, sourceID: sourceID)
            }
            .padding(.horizontal, SpreadMetrics.margin)
            .padding(.top, SpreadMetrics.titleTop)
            .padding(.bottom, 20)
        }
    }
}

/// The cover image in its space (`FittedCover`): the shelf's small copy
/// until the full one loads, else a plain background. A book without a cover
/// shows its title from the start.
struct BookCoverArt: View {
    let page: BookPage
    var thumbnail: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let cover = page.cover ?? thumbnail {
                    FittedCover(image: cover)
                        .transition(.opacity)
                } else if page.book.cover == nil || page.coverFinished {
                    BookTitleCover(title: page.current.title, author: page.authorLine)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.2), value: page.cover)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { page.coverFrame = $0 }
            .accessibilityElement()
            .accessibilityLabel(page.current.title.isEmpty ? "Cover" : "Cover of \(page.current.title)")
    }
}

/// For a book without cover artwork: its title and author on a quiet
/// background.
struct BookTitleCover: View {
    let title: String
    let author: String

    var body: some View {
        LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
            .overlay {
                VStack(spacing: 8) {
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(.system(.largeTitle, design: .serif).bold())
                    Text(author)
                        .font(.system(.title3, design: .serif))
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(40)
                .minimumScaleFactor(0.3)
            }
    }
}

#if DEBUG
#Preview("Cover page") {
    let shell = ShellModel()
    NavigationStack {
        BookCoverPage(book: SampleLibrarySource.books[0], sourceID: SampleLibrarySource.id, source: SampleLibrarySource())
    }
    .environment(shell)
}
#endif
