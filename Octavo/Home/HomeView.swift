import OctavoKit
import SwiftUI

/// The Home tab's list (`TabSplit`, `docs/design/direction.md`, Home): the
/// book you're reading as a large cover, with your other books in progress
/// beneath it. Only books in progress. A book opens its own screen; open,
/// with nothing picked, the right column shows the book you're reading
/// (decision 26). Unfolding here opens nothing.
///
/// A `List` whose selection is the pick, so the folded stack has the
/// system's Back; each book is a row, tagged with its screen.
struct HomeView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let state = HomeState(library)
        List(selection: shell.pickBinding(.home)) {
            rows(state)
        }
        .listStyle(.plain)
        // The banners' row takes no room without a banner.
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await library.loadHome() }
        .navigationTitle("Home")
        .toolbarTitleDisplayMode(.inlineLarge)
        // Each book's place as the server has it, so the rows show where
        // the books open (`BookPlaces`): when Home shows, when its books
        // change, and when the app comes back (not under the reader).
        .onAppear { refreshPlaces() }
        .onChange(of: library.continueReading.map(\.id)) { refreshPlaces() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, shell.reader.reading == nil else { return }
            refreshPlaces(again: true)
        }
    }

    @ViewBuilder
    private func rows(_ state: HomeState) -> some View {
        VStack(spacing: 12) { HomeBannersSlot() }
            .padding(.horizontal, SpreadMetrics.margin)
            .listRow(top: 0, bottom: 0)
        switch state {
        case .noLibrary:
            NoLibraryInvitation()
                .fillsList()
        case .loading:
            CurrentBookPlaceholder(coverWidth: Self.coverWidth)
                .padding(.horizontal, SpreadMetrics.margin)
                .listRow(top: 8)
            ForEach(0..<3, id: \.self) { _ in
                ContinueReadingRowPlaceholder(coverHeight: ContinueReadingRow.standardCoverHeight, verticalPadding: 6)
                    .padding(.horizontal, 14)
                    .listRow(top: 1, bottom: 1)
            }
        case .nothingInProgress:
            invitation
                .fillsList()
        case .reading(let books):
            CurrentBook(book: books[0], coverWidth: Self.coverWidth)
                .padding(.horizontal, SpreadMetrics.margin)
                .listRow(top: 8)
                .tag(ShellRoute.cover(books[0]))
            if books.count > 1 {
                AlsoReadingHeading()
                    .padding(.horizontal, SpreadMetrics.margin)
                    .listRow(top: 14, bottom: 6)
                ForEach(books.dropFirst()) { book in
                    ContinueReadingRow(book: book, progress: shell.places.progress(of: book))
                        .padding(.horizontal, 14)
                        .listRow(top: 1, bottom: 1)
                        .tag(ShellRoute.cover(book))
                }
            }
        }
    }

    @ViewBuilder
    private var invitation: some View {
        if !library.continueReadingFailed {
            // Frame 25.
            EmptyInvitation(
                symbol: "books.vertical", title: "Nothing in progress",
                message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
            ) { shell.select(.library) }
        } else if library.homeProblems.isEmpty {
            EmptyInvitation(
                symbol: "exclamationmark.triangle", title: "Couldn’t load your books in progress",
                message: library.hasSeveralServers ? "Your servers didn’t send them." : "The server didn’t send them.", actionTitle: "Try again"
            ) { Task { await library.loadHome() } }
        }
        // Otherwise the banner says why, and retries.
    }

    private func refreshPlaces(again: Bool = false) {
        for book in library.continueReading {
            shell.places.refreshRow(book, again: again)
        }
    }

    private static let coverWidth: CGFloat = 190
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



/// The current book's shapes while Home loads.
struct CurrentBookPlaceholder: View {
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


struct AlsoReadingHeading: View {
    var body: some View {
        Text("Also reading")
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
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
struct ContinueReadingRowPlaceholder: View {
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
