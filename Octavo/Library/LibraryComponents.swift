import OctavoKit
import SwiftUI

// The pieces Home and the Library are built from: covers that open a book,
// grids, list rows and the chips.

/// Opens `route` like `ShellLink` (pushed folded, beside or shifted along
/// unfolded) for things that aren't list rows: a cover in a grid, a Home row.
/// The label learns whether the pane beside shows its screen.
struct OpenButton<Label: View>: View {
    let route: ShellRoute
    @ViewBuilder let label: (_ isOpen: Bool) -> Label
    @Environment(ShellModel.self) private var shell
    @Environment(\.pane) private var pane

    var body: some View {
        let isOpen = route.isSameScreen(as: pane.opened)
        Button {
            shell.open(route, from: pane)
        } label: {
            label(isOpen)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

/// A book's cover at a 2:3 shape, as the grids and rows show it.
struct BookCover: View {
    let book: SourcedBook
    var cornerRadius: CGFloat = 4

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { CoverImage(book: book) }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

/// Covers in a grid (frames 02, 30, 32), each opening the book's cover page;
/// a series numbers them. Loads the next page as the end scrolls into view.
struct BookGrid: View {
    let books: [SourcedBook]
    var numbered = false
    var loadMore: () async -> Void = {}

    /// Three across folded, four left of the hinge, three right of it.
    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(books) { book in
                OpenButton(route: .cover(book)) { isOpen in
                    VStack(spacing: 4) {
                        BookCover(book: book)
                            .overlay {
                                if isOpen {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.accentColor, lineWidth: 3)
                                }
                            }
                        if numbered {
                            Text(book.book.series?.position.map(Self.number) ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel(Self.accessibilityLabel(book.book, numbered: numbered))
                .onAppear {
                    if book.id == books.last?.id { Task { await loadMore() } }
                }
            }
        }
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

/// The Library's chips (frame 02): All, Collections, Series, Authors for
/// BookOrbit, the feed's own entries for OPDS. They switch the Library in
/// place (decision 23).
struct ChipBar: View {
    let chips: [LibraryEntry]
    let selected: LibraryLink?
    let select: (LibraryLink) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    let isSelected = chip.link == selected
                    Button(chip.title) { select(chip.link) }
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: .capsule)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
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
