import OctavoKit
import SwiftUI

/// The Home tab (frames 01, 38): Continue reading, from the server and the
/// iPhone, then the server's newest books in a row that scrolls sideways.
/// Unfolded, the first book's cover page sits right of the hinge; tapping
/// another book switches it (decision 26).
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
                    // Frame 25.
                    VStack(spacing: 0) {
                        ConnectionBannerSlot()
                            .padding(.horizontal, 20)
                        EmptyInvitation(
                            symbol: "books.vertical", title: "Nothing in progress",
                            message: "Pick a book from your Library to start reading.", actionTitle: "Open Library"
                        ) { shell.tab = .library }
                    }
                } else {
                    content(server)
                }
            } else {
                NoLibraryInvitation()
            }
        }
        .onChange(of: library.continueReading.first, initial: true) { _, book in
            shell[path: .home].companion = book.map { .cover($0) }
        }
    }

    private func content(_ server: LibraryServer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ConnectionBannerSlot()
                    .padding(.horizontal, 20)
                heading("Continue reading")
                VStack(spacing: 2) {
                    ForEach(library.continueReading) { ContinueReadingRow(book: $0) }
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

/// A book in progress: its cover, title, place and progress bar. Selected
/// while the pane beside shows it.
struct ContinueReadingRow: View {
    let book: SourcedBook

    var body: some View {
        OpenButton(route: .cover(book)) { isOpen in
            HStack(spacing: 12) {
                BookCover(book: book, cornerRadius: 2)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                        .lineLimit(1)
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: book.book.progress ?? 0)
                        .padding(.top, 2)
                }
            }
            .padding(6)
            .background(isOpen ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
        }
    }

    /// "30%". The chapter joins it once the reader (#17) records one.
    private var place: String {
        book.book.progress.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "Not started"
    }
}

/// The newest books, one row of covers that scrolls sideways.
struct NewBooksRow: View {
    let books: [SourcedBook]
    @Environment(\.pane) private var pane

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(books) { book in
                    OpenButton(route: .cover(book)) { isOpen in
                        BookCover(book: book)
                            .overlay {
                                if isOpen {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.accentColor, lineWidth: 3)
                                }
                            }
                    }
                    .frame(width: pane.level == nil ? 106 : 98)
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
