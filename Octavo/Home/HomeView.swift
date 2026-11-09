import OctavoKit
import SwiftUI

/// The Home tab (`docs/design/direction.md`, Home): the book you're reading
/// as a large cover, with your other books in progress beneath it folded;
/// unfolded its cover fills the left page as on its folded screen
/// (decision 37), and the others are on the right page. Only books in
/// progress, but for the newest books filling the right page when there are
/// one or two. A book opens its own screen, and unfolded the current book has
/// Open; unfolding here opens nothing. The tab's top screen (`TabStack`).
struct HomeView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.spread) private var spread

    var body: some View {
        let state = HomeState(library)
        // Unfolded, the book you're reading has the left page to itself, with
        // no title over it.
        let titled = !(spread.isTwoPages && state.showsBooks)
        content(state)
            .navigationTitle(titled ? "Home" : "")
            .toolbarTitleDisplayMode(titled ? .large : .inline)
    }

    @ViewBuilder
    private func content(_ state: HomeState) -> some View {
        switch state {
        case .noLibrary:
            NoLibraryInvitation()
        case .loading:
            HomeContent(books: nil)
        case .nothingInProgress:
            // The Library's newest books beside the invitation, not beside a
            // problem.
            EmptyPages(server: library.continueReadingFailed ? nil : library.server?.id) {
                VStack(spacing: 0) {
                    VStack(spacing: 12) { HomeBannersSlot() }
                        .padding(.horizontal, SpreadMetrics.margin)
                    if !library.continueReadingFailed {
                        // Frame 25.
                        EmptyInvitation(
                            symbol: "books.vertical", title: "Nothing in progress",
                            message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
                        ) { shell.select(.library) }
                        .scrollingOnItsPage()
                    } else if library.homeProblems.isEmpty {
                        EmptyInvitation(
                            symbol: "exclamationmark.triangle", title: "Couldn’t load your books in progress",
                            message: library.hasSeveralServers ? "Your servers didn’t send them." : "The server didn’t send them.", actionTitle: "Try again"
                        ) { Task { await library.loadHome() } }
                        .scrollingOnItsPage()
                    } else {
                        // The banner says why, and retries.
                        Spacer()
                    }
                }
            }
        case .reading(let books):
            HomeContent(books: books)
        }
    }
}

/// What Home shows, decided in one place: its content and its title go by it.
enum HomeState {
    /// No server and no books.
    case noLibrary
    /// The shapes of books, until a server's Continue reading has loaded.
    case loading
    /// The invitation (or why the books didn't come).
    case nothingInProgress
    case reading([SourcedBook])

    init(_ library: LibraryModel) {
        if library.server == nil, !library.hasBooks {
            self = .noLibrary
        } else if library.server != nil, !library.homeLoaded {
            self = .loading
        } else if library.continueReading.isEmpty {
            self = .nothingInProgress
        } else {
            self = .reading(library.continueReading)
        }
    }

    /// Books in progress, or their shapes: not an invitation.
    var showsBooks: Bool {
        switch self {
        case .loading, .reading: true
        case .noLibrary, .nothingInProgress: false
        }
    }
}

/// The book you're reading and the others in progress: one column folded,
/// the current book on the left page and the others on the right unfolded.
/// `books` is `nil` until Home has loaded, and shows placeholders.
struct HomeContent: View {
    let books: [SourcedBook]?
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Each book's place as the server has it, so the rows show where
        // the books open (`BookPlaces`): when Home shows, when its books
        // change, and when the app comes back (not under the reader).
        layout
            .onAppear { refreshPlaces() }
            .onChange(of: books?.map(\.id)) { refreshPlaces() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, shell.reader.reading == nil else { return }
                refreshPlaces(again: true)
            }
    }

    private func refreshPlaces(again: Bool = false) {
        for book in books ?? [] {
            shell.places.refreshRow(book, again: again)
        }
    }

    private var layout: some View {
        SpreadPages(alignment: .top) { _ in
            CurrentBookPage(book: books?.first)
        } right: { width in
            AlsoReadingPage(books: others, width: width)
        } folded: {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        HomeBannersSlot()
                        current(coverWidth: 190)
                    }
                    .padding(.horizontal, SpreadMetrics.margin)
                    AlsoReading(books: others)
                }
                .padding(.bottom, 20)
            }
        }
        .refreshable { await library.loadHome() }
    }

    @ViewBuilder
    private func current(coverWidth: CGFloat) -> some View {
        if let book = books?.first {
            CurrentBook(book: book, coverWidth: coverWidth)
        } else {
            CurrentBookPlaceholder(coverWidth: coverWidth)
        }
    }

    /// `nil` while loading.
    private var others: [SourcedBook]? {
        books.map { Array($0.dropFirst()) }
    }
}

/// The book you're reading: its cover, large, then its title, author and
/// place. Opens the book's screen.
struct CurrentBook: View {
    let book: SourcedBook
    let coverWidth: CGFloat
    @Environment(ShellModel.self) private var shell

    var body: some View {
        // Where the book opens, as its screen shows it (`BookPlaces`).
        let progress = shell.places.progress(of: book)
        OpenButton(route: .cover(book)) {
            VStack(alignment: .leading, spacing: 14) {
                BookCover(book: book, cornerRadius: 6, size: .full)
                    .overlay(alignment: .bottomTrailing) { CoverBadge(book: book, size: 26) }
                    .frame(width: coverWidth)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                        .font(.title2.bold())
                        .lineLimit(untilLargerText: 2)
                    if !book.book.authors.isEmpty {
                        Text(book.book.authors.formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                            .lineLimit(untilLargerText: 1)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(BookPage.placeLine(progress: progress, server: shell.library.label(for: book)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress ?? 0)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityValue(shell.marks(of: book).accessibilityValue)
    }
}

/// Unfolded, the book you're reading has the left page: its cover edge to
/// edge on its blur, as the folded book's screen draws it (`BookCoverArt`),
/// with a glass strip over its foot, 8 pt inside the safe area as the folded
/// sheet is (Adam, 2026-11-09): the title, place and Open (decision 37).
/// Open moves this cover onto the right page as a book's screen does
/// (`CoverSpots`). `nil` while Home loads.
struct CurrentBookPage: View {
    let book: SourcedBook?
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @State private var cover = LoadedCover()

    var body: some View {
        // A page that fits, in a scroll view all the same so it pulls to
        // refresh, as the right page does. The cover stays put behind it.
        GeometryReader { proxy in
            ScrollView {
                page
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .scrollBounceBehavior(.always)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background {
            Group {
                if let book {
                    BookCoverArt(
                        // The shelf's copy until the full one loads, as on the
                        // book's screen.
                        image: cover.image ?? library.covers.cachedImage(for: book, size: .full)
                            ?? library.covers.cachedImage(for: book, size: .thumbnail),
                        finished: book.book.cover == nil || cover.finished,
                        title: book.book.title, author: book.book.authors.formatted(.list(type: .and)),
                        book: book.id, screen: .home
                    )
                    // The cover's button below says what it is.
                    .accessibilityHidden(true)
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .ignoresSafeArea(edges: .vertical)
        }
        .loadingCover(of: book, size: .full, into: $cover)
    }

    private var page: some View {
        VStack(spacing: 12) {
            if let book {
                OpenButton(route: .cover(book)) {
                    Color.clear.contentShape(.rect)
                }
                .frame(maxHeight: .infinity)
                .accessibilityLabel(book.book.title.isEmpty ? "Cover" : "Cover of \(book.book.title)")
                .accessibilityValue(shell.marks(of: book).accessibilityValue)
                CurrentBookStrip(book: book)
            } else {
                Spacer()
                RoundedRectangle(cornerRadius: 28)
                    .fill(.quaternary)
                    .frame(height: 88)
                    .accessibilityHidden(true)
            }
        }
        .padding(8)
    }
}

/// The left page's strip: the title on one line over the place, Open on the
/// right of both, and a progress line under them, as a book's folded sheet has
/// them. Until the book is on the iPhone, Open is Download; a download's
/// progress and problems show in its place (decision 22). The title and place
/// open the book's screen.
private struct CurrentBookStrip: View {
    let book: SourcedBook
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let page = shell.pages.page(for: book)
        let place = BookPlace(page: page, sourceID: book.source, shell: shell)
        VStack(alignment: .leading, spacing: 12) {
            LargerTextStack(spacing: 12) {
                OpenButton(route: .cover(book)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                            .font(.headline)
                            .lineLimit(untilLargerText: 1)
                        Text(place.problem ?? BookPage.placeLine(progress: place.progress, server: library.label(for: book)))
                            .font(.subheadline)
                            .foregroundStyle(.secondaryOnGlass)
                            // A problem says what to do, so it may wrap.
                            .lineLimit(untilLargerText: place.problem == nil ? 1 : 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                if let source = library.source(for: book.source) {
                    BookOpenButton(page: page, source: source, sourceID: book.source, fillsWidth: size.isAccessibilitySize)
                        .fixedSize(horizontal: !size.isAccessibilitySize, vertical: !size.isAccessibilitySize)
                }
            }
            ProgressView(value: place.progress ?? 0)
        }
        // At the largest text sizes, the cover gives way.
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 28))
        .environment(\.openBook, EnvironmentAction(id: book.source) { opened in
            shell.reader.open(SourcedBook(source: book.source, book: opened))
        })
        .environment(\.downloadBook, EnvironmentAction(id: book.source) { downloading in
            shell.downloadBook(SourcedBook(source: book.source, book: downloading))
        })
    }
}

/// The current book's shapes while Home loads.
private struct CurrentBookPlaceholder: View {
    let coverWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(width: coverWidth)
            Text(verbatim: "A book’s title\nIts author")
                .font(.title2.bold())
                .redacted(reason: .placeholder)
        }
        .accessibilityHidden(true)
    }
}

/// Your other books in progress beneath the current book, folded, most recent
/// first.
struct AlsoReading: View {
    /// `nil` while loading.
    let books: [SourcedBook]?

    var body: some View {
        if books?.isEmpty != true {
            VStack(alignment: .leading, spacing: 8) {
                AlsoReadingHeading()
                    .padding(.horizontal, SpreadMetrics.margin)
                VStack(spacing: 2) {
                    ContinueReadingRows(books: books)
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

private struct AlsoReadingHeading: View {
    var body: some View {
        Text("Also reading")
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The right page unfolded: your other books, most recent first, in rows that
/// grow to fill the page, from today's size with seven books to the tallest
/// with two. Larger text scrolls instead. With one other book or none, the
/// Library's newest books use the room; with none and no newest books to show,
/// it says so and points to the Library.
struct AlsoReadingPage: View {
    /// `nil` while loading.
    let books: [SourcedBook]?
    let width: CGFloat
    /// The banners and heading, which the rows share the page with.
    @State private var headerHeight: CGFloat = 0
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    private static let topPadding = SpreadMetrics.titleTop + 6
    private static let bottomPadding: CGFloat = 12
    /// One row above the newest books.
    private static let coverHeightAboveShelf: CGFloat = 180

    var body: some View {
        let newest = newest
        if let books, books.isEmpty, newest == nil {
            VStack(spacing: 0) {
                VStack(spacing: 12) { HomeBannersSlot() }
                    .padding(.horizontal, SpreadMetrics.margin)
                    .padding(.top, library.homeProblems.isEmpty ? 0 : Self.topPadding)
                EmptyInvitation(
                    symbol: "books.vertical", title: "Nothing else in progress",
                    message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
                ) { shell.select(.library) }
                .scrollingOnItsPage()
            }
        } else {
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 12) {
                            HomeBannersSlot()
                            if books?.isEmpty != true { AlsoReadingHeading() }
                        }
                        .padding(.horizontal, SpreadMetrics.margin)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { headerHeight = $0 }
                        if books?.isEmpty != true {
                            let rows = books?.count ?? 3
                            let gap: CGFloat = rows > 4 ? 10 : 16
                            VStack(spacing: 0) {
                                ContinueReadingRows(
                                    books: books,
                                    coverHeight: newest == nil
                                        ? Self.coverHeight(rows: rows, gap: gap, room: room(pageHeight: proxy.size.height))
                                        : Self.coverHeightAboveShelf,
                                    verticalPadding: gap / 2
                                )
                            }
                            .padding(.horizontal, 14)
                        }
                        if let newest {
                            LibraryShelf(entry: newest.entry, source: newest.source, maxRows: books?.isEmpty == true ? 3 : 2, hiding: inProgress)
                                .environment(\.spread, Spread(width: width, pages: nil))
                                .padding(.top, books?.isEmpty == true ? 0 : 12)
                        }
                    }
                    .padding(.top, Self.topPadding)
                    .padding(.bottom, Self.bottomPadding)
                }
            }
        }
    }

    private var inProgress: Set<SourcedBook.ID> {
        Set(library.continueReading.map(\.id))
    }

    /// The Library's newest books, with one other book in progress or none,
    /// if there are covers to show that aren't already on the screen.
    private var newest: (entry: LibraryEntry, source: LibrarySourceID)? {
        guard let books, books.count < 2, let source = library.server?.id, let root = library.connection(source)?.root,
              let entry = LibraryView.newest(root), let feed = library.feed(entry.link, from: source),
              LibraryShelf.hasCovers(feed, from: source, hiding: inProgress)
        else { return nil }
        return (entry, source)
    }

    /// The height the rows share.
    private func room(pageHeight: CGFloat) -> CGFloat {
        pageHeight - Self.topPadding - Self.bottomPadding - headerHeight - 4
    }

    /// Each row's cover, `gap` apart, in `room`: as tall as they fit, between
    /// today's size and the tallest.
    static func coverHeight(rows: Int, gap: CGFloat, room: CGFloat) -> CGFloat {
        let height = room / CGFloat(max(rows, 1)) - gap
        return min(max(height, ContinueReadingRow.standardCoverHeight), ContinueReadingRow.tallestCoverHeight)
    }
}

/// The rows, or their shapes while Home loads (`books` is `nil`).
private struct ContinueReadingRows: View {
    let books: [SourcedBook]?
    var coverHeight = ContinueReadingRow.standardCoverHeight
    var verticalPadding: CGFloat = 6
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let books {
            ForEach(books) { book in
                ContinueReadingRow(
                    book: book, progress: shell.places.progress(of: book),
                    coverHeight: coverHeight, verticalPadding: verticalPadding
                )
            }
        } else {
            ForEach(0..<3, id: \.self) { _ in
                ContinueReadingRowPlaceholder(coverHeight: coverHeight, verticalPadding: verticalPadding)
            }
        }
    }
}

/// A book in progress: its cover, title, place and progress bar. Taller, it
/// also has its author, and more of its title.
struct ContinueReadingRow: View {
    static let standardCoverHeight: CGFloat = 72
    static let tallestCoverHeight: CGFloat = 240

    let book: SourcedBook
    let progress: Double?
    var coverHeight = ContinueReadingRow.standardCoverHeight
    var verticalPadding: CGFloat = 6
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    /// Past the size of a shelf's cover, and with room for more words.
    private var isTall: Bool { coverHeight > 100 }

    var body: some View {
        OpenButton(route: .cover(book)) {
            HStack(spacing: 12) {
                BookCover(book: book, cornerRadius: isTall ? 4 : 2, size: isTall ? .full : .thumbnail)
                    .overlay(alignment: .bottomTrailing) { CoverBadge(book: book, size: isTall ? 20 : 14) }
                    .frame(width: coverHeight * 2 / 3)
                    .shadow(color: .black.opacity(isTall ? 0.14 : 0), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                        .font(isTall ? .headline : .body)
                        .lineLimit(untilLargerText: isTall ? 3 : 1)
                    if isTall, !book.book.authors.isEmpty {
                        Text(book.book.authors.formatted(.list(type: .and)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(untilLargerText: 1)
                    }
                    Text(BookPage.placeLine(progress: progress, server: library.label(for: book)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, isTall ? 6 : 0)
                    ProgressView(value: progress ?? 0)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, verticalPadding)
        }
        .accessibilityValue(shell.marks(of: book).accessibilityValue)
    }
}

/// A row's shapes while Home loads.
private struct ContinueReadingRowPlaceholder: View {
    let coverHeight: CGFloat
    let verticalPadding: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.quaternary)
                .frame(width: coverHeight * 2 / 3, height: coverHeight)
            Text(verbatim: "A book’s title\n30%")
                .redacted(reason: .placeholder)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, verticalPadding)
        .accessibilityHidden(true)
    }
}
