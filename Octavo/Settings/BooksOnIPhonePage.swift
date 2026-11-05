import OctavoKit
import SwiftUI

/// Storage: the books downloaded to this iPhone, with what each takes
/// (Adam, 2026-11-02). Sorted as the reader picks, largest first to start
/// with; a swipe removes one, keeping its place, as the details' Remove
/// download does. Remove all downloads asks first. The rows open nothing.
///
/// Imported books (and the sample book) are listed too. Removing one
/// always asks, since it's the only copy, and Remove all downloads leaves
/// them (Adam, 2026-11-02).
struct BooksOnIPhonePage: View {
    @Environment(ShellModel.self) private var shell
    @Environment(LibraryModel.self) private var library
    @AppStorage(DownloadOrder.key) private var order = DownloadOrder.size
    @State private var confirmsRemovingAll = false
    @State private var removingImported: SourcedBook?

    var body: some View {
        let books = order.sorted(shell.downloads())
        if books.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Books on iPhone")
                ContentUnavailableView(
                    "No books on iPhone", systemImage: "book.closed",
                    description: Text("Books you download or import show here.")
                )
            }
        } else {
            list(books)
        }
    }

    private func list(_ books: [DownloadedBook]) -> some View {
        SettingsPageList(title: "Books on iPhone") {
            Section {
                ForEach(books) { book in
                    DownloadedBookRow(book: book)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Remove", role: book.book.source == .files ? nil : .destructive) {
                                if book.book.source == .files {
                                    removingImported = book.book
                                } else {
                                    shell.opener.removeDownload(book.book)
                                }
                            }
                            .tint(.red)
                        }
                }
            } header: {
                HStack {
                    Text(books.summary(books: true))
                    Spacer(minLength: 8)
                    Menu {
                        Picker("Sort by", selection: $order) {
                            ForEach(DownloadOrder.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(order.title)
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                        }
                    }
                    .accessibilityLabel("Sort by \(order.title)")
                }
                .textCase(nil)
            } footer: {
                if let server = library.server {
                    Text("Removing a book keeps your place in it. You can download it again from \(library.hasSeveralServers ? "its server" : server.name).")
                }
            }
            let downloads = books.filter { $0.book.source != .files }
            if !downloads.isEmpty {
                Section {
                    Button("Remove all downloads", role: .destructive) { confirmsRemovingAll = true }
                }
            }
        }
        .alert("Remove all downloads?", isPresented: $confirmsRemovingAll) {
            Button("Remove all downloads", role: .destructive) { shell.opener.removeAllDownloads() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(books.filter { $0.book.source != .files }.summary(books: true)). Your places in them are kept.")
        }
        .confirmRemovingImported($removingImported)
    }
}

/// A downloaded book: its cover, title and author, and its size.
private struct DownloadedBookRow: View {
    let book: DownloadedBook

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(book: book.book)
                .frame(width: 34, height: 51)
                .clipShape(.rect(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(book.book.book.title)
                    .lineLimit(1)
                if let author = book.book.book.authors.first {
                    Text(author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: book.size, countStyle: .file))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Asks before an imported book (or the sample book) goes: it's the only
    /// copy (Adam, 2026-11-02).
    func confirmRemovingImported(_ book: Binding<SourcedBook?>) -> some View {
        modifier(ConfirmRemovingImported(book: book))
    }
}

private struct ConfirmRemovingImported: ViewModifier {
    @Binding var book: SourcedBook?
    @Environment(ShellModel.self) private var shell

    func body(content: Content) -> some View {
        content.confirmationDialog(
            book.map { "Remove “\($0.book.title.isEmpty ? "Untitled" : $0.book.title)” from this iPhone?" } ?? "",
            isPresented: Binding(get: { book != nil }, set: { if !$0 { book = nil } }),
            titleVisibility: .visible,
            presenting: book
        ) { removing in
            Button("Remove", role: .destructive) {
                withAnimation { shell.removeImported(removing) }
            }
        } message: { removing in
            Text(removing.removalMessage)
        }
    }
}

nonisolated extension SourcedBook {
    /// Why removing an imported book is different from removing a download.
    var removalMessage: String {
        isSample
            ? "Are you sure? This book cannot be recovered."
            : "It was imported from Files, so it can’t be downloaded again. Import it again and it opens where you left it."
    }
}
