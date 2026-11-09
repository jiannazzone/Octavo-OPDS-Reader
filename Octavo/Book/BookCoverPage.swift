import OctavoKit
import SwiftUI

/// A book's screen (`docs/design/direction.md`, A book's screen).
///
/// - Folded, the cover on its blur (`FittedCover`) fills the screen, running
///   under the side column and the camera, with a glass sheet at the bottom:
///   the title, the place, Download and Open; pulled up, the details. Tapping
///   the cover while the details show returns to the strip.
/// - Unfolded, Cover | Details: the cover on its blur fills the left page and
///   the same summary and details sit on the right page.
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let sourced = SourcedBook(source: sourceID, book: book)
        let page = shell.pages.page(for: sourced)
        // The shelf's cover, until the full-size one loads: the screen
        // slides in with a cover on it, not an empty frame.
        let thumbnail = shell.library.covers.cachedImage(for: sourced, size: .thumbnail)
        Group {
            SpreadPages { _ in
                BookCoverArt(page: page, thumbnail: thumbnail, book: sourced.id)
                    .ignoresSafeArea(edges: .vertical)
            } right: { _ in
                BookInfoPage(page: page, source: source, sourceID: sourceID)
            } folded: {
                ZStack(alignment: .bottom) {
                    // Open, not under the list beside it (`TabSplit`).
                    BookCoverArt(page: page, thumbnail: thumbnail, book: sourced.id)
                        .ignoresSafeArea(edges: sizeClass == .compact ? .all : [.vertical, .trailing])
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
            shell.opener.clearFailure(sourced)
            shell.places.refresh(sourced)
        }

        .onChange(of: page.details?.book) { _, book in
            // A mark set before they arrived is newer than they are.
            guard let book, page.markedFinished == nil else { return }
            shell.library.detailsLoaded(SourcedBook(source: sourceID, book: book))
        }
        // Downloaded: its place can come from KOReader now (question 4).
        .onChange(of: shell.opener.status(of: sourced) == .downloaded) { _, downloaded in
            if downloaded { shell.places.refresh(sourced) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Not under the reader: its own pushes keep the place current.
            guard phase == .active, shell.reader.reading == nil else { return }
            shell.places.refresh(sourced)
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

/// The cover image in its space (`FittedCover`): on a book's screen the
/// shelf's small copy until the full one loads, else a plain background. A
/// book without a cover shows its title once there's nothing more to load.
/// Home's left page unfolded draws its cover with this too, as the folded
/// book's screen does (decision 37).
struct BookCoverArt: View {
    let image: UIImage?
    /// Nothing more to load: without an image, the title shows.
    let finished: Bool
    let title: String
    let author: String
    /// The book, and the screen it's on, for where its cover is
    /// (`ReaderPresenter.coverSpots`).
    let book: SourcedBook.ID
    let screen: CoverSpots.Screen
    @Environment(ShellModel.self) private var shell
    @Environment(\.spread) private var layout
    /// Where it was last laid out, to report again on appearing.
    @State private var frame: CGRect?
    @State private var reporter = UUID()

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let image {
                    FittedCover(image: image)
                        .transition(.opacity)
                } else if finished {
                    BookTitleCover(title: title, author: author)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.2), value: image)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onChange(of: spot) { report() }
            .onAppear { report() }
            .onDisappear { shell.reader.coverSpots.gone(from: screen, reporter: reporter) }
            .accessibilityElement()
            .accessibilityLabel(title.isEmpty ? "Cover" : "Cover of \(title)")
    }

    private var spot: CoverSpot? {
        frame.map { CoverSpot(book: book, frame: $0, image: image, title: title, author: author, spread: layout.isTwoPages) }
    }

    private func report() {
        if let spot { shell.reader.coverSpots.report(spot, on: screen, from: reporter) }
    }
}

extension BookCoverArt {
    /// On the book's own screen.
    init(page: BookPage, thumbnail: UIImage?, book: SourcedBook.ID) {
        self.init(
            image: page.cover ?? thumbnail, finished: page.book.cover == nil || page.coverFinished,
            title: page.current.title, author: page.authorLine, book: book, screen: .book(book)
        )
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
