import OctavoKit
import SwiftUI

// The pieces Home and the Library are built from: covers that open a book,
// grid cells and list rows.

/// Opens `route` like `ShellLink`, for things that aren't list rows: a cover
/// in a grid, a Home row.
struct OpenButton<Label: View>: View {
    let route: ShellRoute
    @ViewBuilder let label: () -> Label
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Button {
            shell.push(route)
        } label: {
            label()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A book's cover at a 2:3 shape, as the grids and rows show it.
struct BookCover: View {
    let book: SourcedBook
    var cornerRadius: CGFloat = 4
    /// `.full` for a cover shown large, such as Home's current book.
    var size: LibraryCoverSize = .thumbnail

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { CoverImage(book: book, size: size) }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

/// A cover in a grid, opening the book's screen; a series numbers it.
struct BookGridCell: View {
    let book: SourcedBook
    var numbered = false
    @Environment(ShellModel.self) private var shell

    var body: some View {
        OpenButton(route: .cover(book)) {
            VStack(spacing: 4) {
                BookCover(book: book)
                    .overlay(alignment: .bottomTrailing) { DownloadBadge(book: book.book) }
                if numbered {
                    Text(book.book.series?.position.map(Self.number) ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityLabel(Self.accessibilityLabel(book.book, numbered: numbered))
        .accessibilityValue(DownloadBadge.accessibilityValue(shell.opener.status(of: book.book)))
    }

    /// 1, 2, 2.5.
    static func number(_ position: Double) -> String {
        position.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func accessibilityLabel(_ book: LibraryBook, numbered: Bool) -> String {
        let title = book.title.isEmpty ? "Untitled" : book.title
        guard numbered, let position = book.series?.position else { return title }
        return "\(number(position)). \(title)"
    }
}

/// On a cover: a check once the book is on the iPhone, a ring while it
/// downloads, nothing otherwise (`docs/design/direction.md`, Getting books
/// onto the iPhone). A dark disc, so it reads on any cover.
struct DownloadBadge: View {
    let book: LibraryBook
    var size: CGFloat = 22
    @Environment(ShellModel.self) private var shell

    var body: some View {
        switch shell.opener.status(of: book) {
        case .downloaded:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.6), in: .circle)
                .padding(size / 4)
                .transition(.scale.combined(with: .opacity))
        case .downloading(let fraction, _):
            Circle()
                .trim(from: 0, to: max(fraction, 0.02))
                .stroke(.white, style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(size / 5)
                .background(.black.opacity(0.6), in: .circle)
                .frame(width: size, height: size)
                .padding(size / 4)
                .animation(.linear(duration: 0.2), value: fraction)
        case .notDownloaded, .failed:
            EmptyView()
        }
    }

    /// For the cover's own label: "Downloaded", "Downloading, 40%".
    static func accessibilityValue(_ status: BookOpener.Status) -> String {
        switch status {
        case .downloaded: "Downloaded"
        case .downloading(let fraction, _): "Downloading, \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case .notDownloaded, .failed: ""
        }
    }
}

/// A row for a list entry: a collection, smart scope or series with three of
/// its covers (frame 29), an author or an OPDS entry with its count.
struct EntryRow: View {
    let entry: LibraryEntry
    let source: LibrarySourceID
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ShellLink(.feed(entry, from: source)) {
            HStack(spacing: 12) {
                if showsCovers {
                    covers
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.kind == .author ? entry.sortName ?? entry.title : entry.title)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if entry.kind == .author, let count = entry.count {
                    Spacer(minLength: 8)
                    Text(count, format: .number)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var showsCovers: Bool {
        [.collection, .smartCollection, .series].contains(entry.kind)
    }

    /// "42 books", "9 books · smart scope", "Arthur Conan Doyle · 3 books".
    private var detail: String? {
        let count = entry.count.map { $0 == 1 ? "1 book" : "\($0) books" }
        switch entry.kind {
        case .author: return nil
        case .smartCollection: return [count, "smart scope"].compactMap(\.self).joined(separator: " · ")
        case .series: return [entry.subtitle, count].compactMap(\.self).joined(separator: " · ")
        case .collection: return count
        case .feed: return entry.subtitle
        }
    }

    /// The entry's own covers where the library lists them; otherwise the
    /// first books of its list, loaded as the row appears
    /// (`LibraryModel.preview`).
    private var covers: some View {
        let books = previewBooks
        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Group {
                    if index < books.count {
                        BookCover(book: books[index], cornerRadius: 2)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.quaternary)
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
                }
                .frame(width: 22)
            }
        }
        .task(id: entry.link) {
            guard entry.previewCovers.isEmpty else { return }
            await library.preview(entry.link, from: source)?.load()
        }
    }

    private var previewBooks: [SourcedBook] {
        if !entry.previewCovers.isEmpty {
            return entry.previewCovers.prefix(3).enumerated().map { index, cover in
                SourcedBook(source: source, book: LibraryBook(id: LibraryBookID(rawValue: "\(entry.link.rawValue)#\(index)"),
                                                              title: "", cover: cover))
            }
        }
        let books = library.preview(entry.link, from: source)?.books.prefix(3) ?? []
        return books.map { SourcedBook(source: source, book: $0) }
    }
}

/// Authors A–Z (frame 31): sections by the first letter of the sort name,
/// with anything that isn't a letter under #.
nonisolated enum AuthorIndex {
    struct Section: Identifiable, Equatable {
        var letter: String
        var entries: [LibraryEntry]
        var id: String { letter }
    }

    static func sections(_ entries: [LibraryEntry]) -> [Section] {
        let grouped = Dictionary(grouping: entries) { letter(of: $0.sortName ?? $0.title) }
        return grouped.keys
            .sorted { a, b in a == "#" ? false : b == "#" ? true : a < b }
            .map { letter in
                Section(letter: letter, entries: grouped[letter]!.sorted {
                    ($0.sortName ?? $0.title).localizedStandardCompare($1.sortName ?? $1.title) == .orderedAscending
                })
            }
    }

    /// "Émile" files under E.
    static func letter(of name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        guard let first = folded.unicodeScalars.first(where: { !CharacterSet.whitespaces.contains($0) }),
              ("a"..."z").contains(Character(first))
        else { return "#" }
        return String(first).uppercased()
    }
}
