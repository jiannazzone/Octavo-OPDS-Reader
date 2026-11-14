import OctavoKit
import SwiftUI
import UIKit

// The pieces Home and the Library are built from: covers that open a book,
// grid cells and list rows.

/// Opens `route` on top of the current tab: a cover in a grid, a Home row,
/// a row in a list. The one way to, so every one draws its words the same
/// way: as they are, wrapped lines to the leading edge (the system's button
/// centred them at large text sizes).
struct OpenButton<Label: View>: View {
    let route: ShellRoute
    /// A row in a list, which takes a tap anywhere across its width.
    var fillsRow = false
    @ViewBuilder let label: () -> Label
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Button {
            shell.push(route)
        } label: {
            label()
                .frame(maxWidth: fillsRow ? .infinity : nil, alignment: .leading)
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
/// With Titles under covers on (Settings), its title shows beneath, up to
/// two lines, for covers that don't make the book clear.
struct BookGridCell: View {
    let book: SourcedBook
    var numbered = false
    @Environment(ShellModel.self) private var shell
    @AppStorage(LibrarySettings.titlesUnderCoversKey) private var showsTitle = false

    var body: some View {
        OpenButton(route: .cover(book)) {
            VStack(spacing: 4) {
                BookCover(book: book)
                    .overlay(alignment: .bottomTrailing) { CoverBadge(book: book) }
                if numbered {
                    Text(book.book.series?.position.map(Self.number) ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if showsTitle {
                    Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                        .font(.footnote)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(Self.accessibilityLabel(book.book, numbered: numbered))
        .accessibilityValue(shell.marks(of: book).accessibilityValue)
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

/// What a cover says about its book: finished, and on the iPhone or on its
/// way (`docs/design/direction.md`, Getting books onto the iPhone).
struct CoverMarks: Equatable {
    enum Download: Equatable {
        case downloaded
        case downloading(Double)
    }

    var finished: Bool
    /// The server's read status (BookOrbit's, #120). One the place line names
    /// takes the check's place.
    var readStatus: LibraryReadStatus?
    var download: Download?

    init(finished: Bool, readStatus: LibraryReadStatus? = nil, status: BookOpener.Status) {
        self.finished = finished
        self.readStatus = readStatus
        switch status {
        case .downloaded: download = .downloaded
        case .downloading(let fraction, _): download = .downloading(fraction)
        case .notDownloaded, .failed, .protected: download = nil
        }
    }

    /// The status the badge shows: finished, or a status the place line
    /// names (Adam, 2026-11-13). Reading and unread show none.
    var shownStatus: LibraryReadStatus? {
        finished ? .read : readStatus.flatMap { $0.placeWord == nil ? nil : $0 }
    }

    var isEmpty: Bool { shownStatus == nil && download == nil }

    /// For the cover's own label: "Finished, downloaded", "On hold",
    /// "Downloading, 40%".
    var accessibilityValue: String {
        let status = shownStatus?.title
        let download: String? = switch self.download {
        case .downloaded: status == nil ? "Downloaded" : "downloaded"
        case .downloading(let fraction):
            "\(status == nil ? "Downloading" : "downloading"), \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case nil: nil
        }
        return [status, download].compactMap(\.self).joined(separator: ", ")
    }
}

extension ShellModel {
    func marks(of book: SourcedBook) -> CoverMarks {
        CoverMarks(finished: library.isFinished(book), readStatus: library.readStatus(of: book), status: opener.status(of: book))
    }
}

/// On a cover: a check on a finished book (or a BookOrbit status's glyph:
/// a bookmark, pause, forward or cross, #120), then an arrow once it's on the
/// iPhone or a ring while it downloads, nothing otherwise. A dark capsule, so
/// it reads on any cover; with one mark it's a disc.
struct CoverBadge: View {
    let book: SourcedBook
    var size: CGFloat = 22
    @Environment(ShellModel.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let marks = shell.marks(of: book)
        if !marks.isEmpty {
            HStack(spacing: size * 0.08) {
                if let status = marks.shownStatus { symbol(status.symbol, small: status != .read) }
                switch marks.download {
                case .downloaded: symbol("arrow.down.to.line.compact")
                case .downloading(let fraction): ring(fraction)
                case nil: EmptyView()
                }
            }
            .padding(.horizontal, size / 5)
            .frame(height: size)
            .background(.black.opacity(0.6), in: .capsule)
            .padding(size / 4)
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            .accessibilityHidden(true)
        }
    }

    /// `small`: a status's glyph, which at the check's size looks larger
    /// than the check and the arrow (Adam, 2026-11-13).
    private func symbol(_ name: String, small: Bool = false) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.5, weight: .bold))
            .imageScale(small ? .small : .medium)
            .foregroundStyle(.white)
            .frame(width: size * 3 / 5, height: size * 3 / 5)
    }

    private func ring(_ fraction: Double) -> some View {
        Circle()
            .trim(from: 0, to: max(fraction, 0.02))
            .stroke(.white, style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: size * 3 / 5, height: size * 3 / 5)
            .animation(.linear(duration: 0.2), value: fraction)
    }
}

/// A row for a list entry: a collection, smart scope or series with three of
/// its covers (frame 29), an author or an OPDS entry with its count right
/// after its name. No chevron: unfolded it would sit mid-screen.
struct EntryRow: View {
    let entry: LibraryEntry
    let source: LibrarySourceID
    @Environment(LibraryModel.self) private var library

    var body: some View {
        OpenButton(route: .feed(entry, from: source), fillsRow: true) {
            HStack(spacing: 12) {
                if showsCovers {
                    covers
                }
                if entry.kind == .author {
                    AuthorAvatar(entry: entry, source: source)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AuthorIndex.displayName(entry))
                            .lineLimit(untilLargerText: 1)
                        if let detail = entry.listDetail {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .lineLimit(untilLargerText: 1)
                        if let detail = entry.listDetail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(untilLargerText: 1)
                        }
                    }
                }
            }
        }
    }

    private var showsCovers: Bool {
        [.collection, .smartCollection, .series].contains(entry.kind)
    }

    private var covers: some View {
        let books = entry.previewBooks(from: source, library: library)
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
        .loadsPreview(of: entry, from: source)
    }
}

/// A series (or any list of books) as a small stack of its first covers,
/// with its name and count under it: the Series list and the shelves of
/// lists. Opens the entry.
struct EntryTile: View {
    let entry: LibraryEntry
    let source: LibrarySourceID
    @Environment(LibraryModel.self) private var library

    var body: some View {
        OpenButton(route: .feed(entry, from: source)) {
            VStack(alignment: .leading, spacing: 6) {
                CoverStack(books: entry.previewBooks(from: source, library: library))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.kind == .author ? AuthorIndex.displayName(entry) : entry.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    // The count alone: a tile is too narrow for the
                    // series' author as well.
                    if let count = entry.count {
                        Text(count == 1 ? "1 book" : "\(count) books")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
        .loadsPreview(of: entry, from: source)
    }
}

/// Up to three covers, the first in front and the others peeking out
/// behind it, up and to the right.
struct CoverStack: View {
    let books: [SourcedBook]
    static let step: CGFloat = 5

    var body: some View {
        let shown = Array(books.prefix(3))
        ZStack(alignment: .bottomLeading) {
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                    .aspectRatio(2 / 3, contentMode: .fit)
            }
            ForEach(shown.indices.reversed(), id: \.self) { index in
                BookCover(book: shown[index], cornerRadius: 3)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: -1)
                    .offset(x: CGFloat(index) * Self.step, y: -CGFloat(index) * Self.step)
            }
        }
        .padding(.top, 2 * Self.step)
        .padding(.trailing, 2 * Self.step)
        .accessibilityHidden(true)
    }
}

extension LibraryEntry {
    /// "42 books", "9 books · smart scope", "Arthur Conan Doyle · 3 books",
    /// an author's "1 book".
    var listDetail: String? {
        let count = count.map { $0 == 1 ? "1 book" : "\($0) books" }
        switch kind {
        case .author, .collection: return count
        case .smartCollection: return [count, "smart scope"].compactMap(\.self).joined(separator: " · ")
        case .series: return [subtitle, count].compactMap(\.self).joined(separator: " · ")
        case .feed: return subtitle
        }
    }

    /// The entry's own covers where the library lists them; otherwise the
    /// first books of its list, once loaded (`loadsPreview`). A cover the
    /// server hasn't got shows the entry's name on the front one.
    @MainActor
    func previewBooks(from source: LibrarySourceID, library: LibraryModel) -> [SourcedBook] {
        if !previewCovers.isEmpty {
            return previewCovers.prefix(3).enumerated().map { index, cover in
                SourcedBook(source: source, book: LibraryBook(id: LibraryBookID(rawValue: "\(link.rawValue)#\(index)"),
                                                              title: index == 0 ? title : "", cover: cover))
            }
        }
        let books = library.preview(link, from: source)?.books.prefix(3) ?? []
        return books.map { SourcedBook(source: source, book: $0) }
    }
}

extension View {
    /// Loads the first books of `entry`'s list when the server doesn't list
    /// its covers.
    func loadsPreview(of entry: LibraryEntry, from source: LibrarySourceID) -> some View {
        modifier(PreviewLoader(entry: entry, source: source))
    }
}

private struct PreviewLoader: ViewModifier {
    let entry: LibraryEntry
    let source: LibrarySourceID
    @Environment(LibraryModel.self) private var library

    func body(content: Content) -> some View {
        content.task(id: entry.link) {
            guard entry.previewCovers.isEmpty else { return }
            await library.preview(entry.link, from: source)?.load()
        }
    }
}

/// Authors A–Z: names as people write them ("Jane Austen"), filed by last
/// name ("H. G. Wells" under W), with anything that isn't a letter under #.
nonisolated enum AuthorIndex {
    struct Section: Identifiable, Equatable {
        var letter: String
        var entries: [LibraryEntry]
        var id: String { letter }
    }

    static func sections(_ entries: [LibraryEntry]) -> [Section] {
        let grouped = Dictionary(grouping: entries) { letter(of: sortKey($0)) }
        return grouped.keys
            .sorted { a, b in a == "#" ? false : b == "#" ? true : a < b }
            .map { letter in
                Section(letter: letter, entries: grouped[letter]!.sorted {
                    sortKey($0).localizedStandardCompare(sortKey($1)) == .orderedAscending
                })
            }
    }

    /// "Austen, Jane": the server's sort name when it's last name first,
    /// else made from the name (BookOrbit sends "H. G. Wells" for some).
    static func sortKey(_ entry: LibraryEntry) -> String {
        if let sortName = entry.sortName, sortName.contains(",") { return sortName }
        return sortKey(name: entry.title)
    }

    /// "Austen, Jane", from a name as people write it.
    static func sortKey(name: String) -> String {
        if name.contains(",") { return name }
        let words = name.split(separator: " ")
        guard words.count > 1, let last = words.last else { return name }
        return "\(last), \(words.dropLast().joined(separator: " "))"
    }

    /// "Jane Austen", turning a name sent last name first around.
    static func displayName(_ entry: LibraryEntry) -> String {
        let parts = entry.title.split(separator: ",", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return entry.title }
        return "\(parts[1].trimmingCharacters(in: .whitespaces)) \(parts[0].trimmingCharacters(in: .whitespaces))"
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

/// An author beside their name (Adam, 2026-11-02): their photo if the
/// server has one (BookOrbit's, from the server itself), else their
/// initials on a tint that stays the same for the same name.
struct AuthorAvatar: View {
    let entry: LibraryEntry
    let source: LibrarySourceID
    var size: CGFloat = 36
    @Environment(LibraryModel.self) private var library
    @State private var loaded: UIImage?

    var body: some View {
        let name = AuthorIndex.displayName(entry)
        let tint = Self.tint(for: name)
        let image = loaded ?? entry.portrait.flatMap { library.covers.cachedImage(for: $0, in: source, size: .thumbnail) }
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                tint.opacity(0.18)
                Text(Self.initials(name))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .task(id: entry.portrait) {
            guard let portrait = entry.portrait else { return }
            loaded = await library.portraitImage(portrait, from: source)
        }
        .accessibilityHidden(true)
    }

    /// "JA" for Jane Austen, "HW" for H. G. Wells, "P" for Plato: the first
    /// and last names' first letters.
    nonisolated static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).filter { $0.first?.isLetter == true }
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return String(letters).uppercased()
    }

    nonisolated private static let tints: [Color] = [.purple, .teal, .orange, .blue, .pink, .indigo, .green, .brown]

    nonisolated static func tint(for name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return tints[sum % tints.count]
    }
}

/// The Library's display choices, kept on the iPhone.
enum LibrarySettings {
    /// Titles under covers (Adam, 2026-11-02): off by default.
    static let titlesUnderCoversKey = "library.titlesUnderCovers"
}
