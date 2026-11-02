import OctavoKit
import SwiftUI

/// The Home tab: Continue reading, from the server and the iPhone, then the
/// server's newest books in a row that scrolls sideways. Redone as "your
/// book first" in milestone 5.
struct HomeView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Group {
            if let server = library.server {
                if !library.homeLoaded {
                    VStack {
                        ConnectionBannerSlot()
                            .padding(.horizontal, 20)
                        ProgressView()
                            .frame(maxHeight: .infinity)
                    }
                } else if library.continueReading.isEmpty {
                    VStack(spacing: 0) {
                        ConnectionBannerSlot()
                            .padding(.horizontal, 20)
                        if !library.continueReadingFailed {
                            // Frame 25.
                            EmptyInvitation(
                                symbol: "books.vertical", title: "Nothing in progress",
                                message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
                            ) { shell.select(.library) }
                        } else if library.connectionProblem == nil {
                            EmptyInvitation(
                                symbol: "exclamationmark.triangle", title: "Couldn’t load Continue reading",
                                message: "The server didn’t send it.", actionTitle: "Try again"
                            ) { Task { await library.loadHome() } }
                        } else {
                            // The banner says why, and retries.
                            Spacer()
                        }
                    }
                } else {
                    content(server)
                }
            } else {
                NoLibraryInvitation()
            }
        }
    }

    private func content(_ server: LibraryServer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ConnectionBannerSlot()
                    .padding(.horizontal, 20)
                heading("Continue reading")
                VStack(spacing: 2) {
                    // As the cover's strip shows it: the iPhone's position
                    // if it has one, else the server's (#14). Worked out
                    // here, so closing the reader (which redraws Home)
                    // updates it.
                    ForEach(library.continueReading) { book in
                        ContinueReadingRow(book: book, progress: BookPage.progress(of: book.book))
                    }
                }
                .padding(.horizontal, 14)
                if !library.newBooks.isEmpty {
                    heading("New on \(server.name)")
                        .padding(.top, 10)
                    NewBooksRow(books: library.newBooks)
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable { await library.loadHome() }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.isHeader)
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

/// The newest books, one row of covers that scrolls sideways.
struct NewBooksRow: View {
    let books: [SourcedBook]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(books) { book in
                    OpenButton(route: .cover(book)) {
                        BookCover(book: book)
                            .overlay(alignment: .bottomTrailing) { DownloadBadge(book: book.book) }
                    }
                    .frame(width: 106)
                    .accessibilityLabel(book.book.title)
                }
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        // A sideways scroll view reaches under the side column; stop at the
        // content's edge, as the vertical lists do.
        .clipped()
    }
}
