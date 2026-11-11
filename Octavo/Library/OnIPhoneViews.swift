import OctavoKit
import SwiftUI

// On iPhone (`docs/design/direction.md`, Other ways in): every book whose
// file is on this iPhone, downloaded or imported. The same book as on its
// server's shelves, not a copy.

/// On iPhone, opened from its shelf or by an import, with Sort and Filter
/// (#131).
struct OnIPhoneScreen: View {
    @AppStorage(OnIPhoneOrder.sortKey) private var sort = LibrarySort.title
    @State private var filter = LibraryFilter.all
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let order = OnIPhoneOrder.order(sort, filter)
        // Once per redraw: listing reads every file, and a status every place.
        let all = shell.onIPhoneBooks(sortedBy: order.sort ?? .title)
        OnIPhoneContent(listed: shell.books(all, showing: filter), filter: filter) { filter = .all }
            .modifier(FilteredTitle(filter: filter))
            .toolbar {
                if !all.isEmpty {
                    ListOrderButtons(order: order, sortTitle: OnIPhoneOrder.title) { sort, filter in
                        if let sort { self.sort = sort }
                        self.filter = filter
                    }
                }
            }
    }
}

extension ShellModel {
    /// Where `book` stands by Octavo's own record (#131): finished if
    /// marked, reading once it has a place, else unread. What another
    /// reader did shows only once its place syncs here.
    func status(of book: SourcedBook) -> LibraryFilter {
        status(of: book, saved: nil)
    }

    /// `books` that `filter` shows, listing the saved places once rather
    /// than reading one for each book.
    func books(_ books: [SourcedBook], showing filter: LibraryFilter) -> [SourcedBook] {
        guard filter != .all else { return books }
        let saved = places.store.savedFiles()
        return books.filter { status(of: $0, saved: saved) == filter }
    }

    private func status(of book: SourcedBook, saved: Set<String>?) -> LibraryFilter {
        if library.isFinished(book) { return .finished }
        let progress = saved.map { places.progress(of: book, saved: $0) } ?? places.progress(of: book)
        return progress == nil ? .unread : .reading
    }

    /// The books on the iPhone in `sort` order (`OnIPhoneOrder`).
    func onIPhoneBooks(sortedBy sort: LibrarySort) -> [SourcedBook] {
        _ = library.importedBooks
        return OnIPhoneOrder.sorted(downloads().filter { library.source(for: $0.book.source) != nil }, by: sort).map(\.book)
    }
}

/// The books on the iPhone as a grid across the spread, with their count,
/// and the banner for files an import couldn't take. With no server it is
/// the Library itself, ending with the Have a server? card.
struct OnIPhoneContent: View {
    /// No server yet: the card that offers one.
    var offersServer = false
    /// The books as On iPhone's screen sorted and filtered them. `nil`: all
    /// of them, newest first.
    var listed: [SourcedBook]?
    var filter = LibraryFilter.all
    var showAll: () -> Void = {}
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let books = listed ?? shell.onIPhoneBooks()
        if books.isEmpty, let wording = EmptyListWording(filter: filter) {
            EmptyPages(server: library.server?.id) {
                EmptyInvitation(
                    symbol: "books.vertical", title: wording.title, message: wording.message, actionTitle: "Show All Books", action: showAll
                )
                .scrollingOnItsPage()
            }
        } else if books.isEmpty {
            EmptyPages(server: library.server?.id) {
                VStack(spacing: 14) {
                    ImportFailureBanner()
                        .padding(.horizontal, SpreadMetrics.margin)
                    EmptyInvitation(
                        symbol: "book.closed", title: "No books on \(ThisDevice.name)",
                        message: "Books you download or import show here.", actionTitle: "Import from Files"
                    ) { shell.showFilePicker() }
                    .scrollingOnItsPage()
                    if offersServer {
                        HaveAServerCard()
                            .padding(.horizontal, SpreadMetrics.margin)
                    }
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        // Filtered, the list's name comes first, as on a
                        // server's lists ("On iPhone · 3 books").
                        Text(booksLine(books.count, in: filter == .all ? nil : "On \(ThisDevice.name)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ImportFailureBanner()
                    }
                    .padding(.horizontal, SpreadMetrics.margin)
                    .onLeftPage()
                    SpreadGrid(items: books) { book in
                        BookGridCell(book: book)
                    }
                    if offersServer {
                        HaveAServerCard()
                            .padding(.horizontal, SpreadMetrics.margin)
                            .onLeftPage()
                            .padding(.top, 10)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }
}

/// The Library's last shelf: "On iPhone 5 ›" over one row of its covers.
/// Nothing while the iPhone has no books.
struct OnIPhoneShelf: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let books = shell.onIPhoneBooks()
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    shell.push(.onIPhone)
                } label: {
                    HStack(spacing: 6) {
                        Text("On \(ThisDevice.name)")
                            .font(.title3.weight(.semibold))
                        Text(books.count, format: .number)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.forward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("On \(ThisDevice.name), \(books.count) books")
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, SpreadMetrics.margin)
                .onLeftPage()
                SpreadGrid(items: books, maxRows: 1) { book in
                    BookGridCell(book: book)
                }
            }
        }
    }
}

/// Files the last import couldn't take, and why; OK closes it. The
/// connection banner's warning style.
struct ImportFailureBanner: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let message = ImportFailure.summary(shell.importFailures) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("OK") {
                        withAnimation { shell.importFailures = [] }
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .tint(.orange)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(12)
            .background(Color.orange.opacity(0.14), in: .rect(cornerRadius: 14))
        }
    }
}

/// "Have a server?" under the Library's books while there's none: a
/// dismissible invitation (`docs/design/direction.md`): ✕ and it never
/// comes back. Settings' Add a server stays.
struct HaveAServerCard: View {
    static let dismissedKey = "library.haveAServer.dismissed"
    @AppStorage(Self.dismissedKey) private var dismissed = false
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if !dismissed {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Have a server?")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button("Don’t show again", systemImage: "xmark") {
                        withAnimation { dismissed = true }
                    }
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                }
                Text("Add BookOrbit or an OPDS catalog to read its books here too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add a server") { shell.push(.setup(.choose)) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
        }
    }
}
