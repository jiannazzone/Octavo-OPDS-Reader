import OctavoKit
import SwiftUI

/// The Home tab (`docs/design/direction.md`, Home): the book you're reading
/// as a large cover, with your other books in progress beneath it folded,
/// or on the right page unfolded. Only books in progress; new arrivals live
/// in the Library. A book opens its own screen; unfolding here opens
/// nothing.
struct HomeView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if library.server == nil, !library.hasAddedBooks {
            NoLibraryInvitation()
        } else if library.server != nil, !library.homeLoaded {
            HomeContent(books: nil)
        } else if library.continueReading.isEmpty {
            VStack(spacing: 0) {
                ConnectionBannerSlot()
                    .padding(.horizontal, SpreadMetrics.margin)
                if !library.continueReadingFailed {
                    // Frame 25.
                    EmptyInvitation(
                        symbol: "books.vertical", title: "Nothing in progress",
                        message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
                    ) { shell.select(.library) }
                } else if library.connectionProblem == nil {
                    EmptyInvitation(
                        symbol: "exclamationmark.triangle", title: "Couldn’t load your books in progress",
                        message: "The server didn’t send them.", actionTitle: "Try again"
                    ) { Task { await library.loadHome() } }
                } else {
                    // The banner says why, and retries.
                    Spacer()
                }
            }
        } else {
            HomeContent(books: library.continueReading)
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
    @Environment(\.spread) private var spread
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Each book's place as the server has it, so the rows show where
        // the books open (`BookPlaces`): when Home shows, when its books
        // change, and when the app comes back (not under the reader).
        layout
            .onAppear { refreshPlaces() }
            .onChange(of: books?.map(\.id)) { refreshPlaces() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, shell.reading == nil else { return }
                refreshPlaces(again: true)
            }
    }

    private func refreshPlaces(again: Bool = false) {
        for book in books ?? [] {
            shell.places.refreshRow(book, again: again)
        }
    }

    @ViewBuilder
    private var layout: some View {
        if let pages = spread.pages {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ConnectionBannerSlot()
                        current(coverWidth: 250)
                    }
                    .padding(.horizontal, SpreadMetrics.margin)
                    .padding(.bottom, 20)
                }
                .frame(width: pages.leftWidth)
                Color.clear
                    .frame(width: pages.hingeWidth)
                ScrollView {
                    AlsoReading(books: others, fillsPage: true)
                        .padding(.bottom, 20)
                }
                .frame(width: pages.rightWidth)
            }
            .refreshable { await library.loadHome() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        ConnectionBannerSlot()
                        current(coverWidth: 190)
                    }
                    .padding(.horizontal, SpreadMetrics.margin)
                    AlsoReading(books: others, fillsPage: false)
                }
                .padding(.bottom, 20)
            }
            .refreshable { await library.loadHome() }
        }
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
                    .overlay(alignment: .bottomTrailing) { DownloadBadge(book: book.book, size: 26) }
                    .frame(width: coverWidth)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                        .font(.title2.bold())
                        .lineLimit(2)
                    if !book.book.authors.isEmpty {
                        Text(book.book.authors.formatted(.list(type: .and)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(BookPage.placeLine(progress: progress))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress ?? 0)
                }
            }
            .accessibilityElement(children: .combine)
        }
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

/// Your other books in progress, most recent first. Unfolded it fills the
/// right page, so with nothing else in progress it points to the Library.
struct AlsoReading: View {
    /// `nil` while loading.
    let books: [SourcedBook]?
    let fillsPage: Bool
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let books, books.isEmpty {
            if fillsPage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing else in progress.")
                        .foregroundStyle(.secondary)
                    Button("Browse your Library") { shell.select(.library) }
                }
                .padding(.horizontal, SpreadMetrics.margin)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Also reading")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, SpreadMetrics.margin)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 2) {
                    if let books {
                        ForEach(books) { book in
                            ContinueReadingRow(book: book, progress: shell.places.progress(of: book))
                        }
                    } else {
                        ForEach(0..<3, id: \.self) { _ in ContinueReadingRowPlaceholder() }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

/// A book in progress: its cover, title, place and progress bar.
struct ContinueReadingRow: View {
    let book: SourcedBook
    let progress: Double?

    var body: some View {
        OpenButton(route: .cover(book)) {
            HStack(spacing: 12) {
                BookCover(book: book, cornerRadius: 2)
                    .overlay(alignment: .bottomTrailing) { DownloadBadge(book: book.book, size: 14) }
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                        .lineLimit(1)
                    Text(BookPage.placeLine(progress: progress))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress ?? 0)
                        .padding(.top, 2)
                }
            }
            .padding(6)
        }
    }
}

/// A row's shapes while Home loads.
private struct ContinueReadingRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.quaternary)
                .frame(width: 48, height: 72)
            Text(verbatim: "A book’s title\n30%")
                .redacted(reason: .placeholder)
            Spacer(minLength: 0)
        }
        .padding(6)
        .accessibilityHidden(true)
    }
}
