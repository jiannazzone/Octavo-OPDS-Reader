import OctavoKit
import SwiftUI

/// The Search tab's screen (`docs/design/direction.md`, Search tab): the
/// field under the title on the left page (Adam, 2026-11-01: it slides
/// away with the screen when a result opens, which iOS's own field in the
/// top bar wouldn't). Before typing, your recent searches and the
/// library's lists to browse; then the results, which open their screens
/// in this tab.
struct SearchView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell
    @Environment(\.spread) private var spread

    var body: some View {
        // With no server yet, the imported books alone.
        if library.server != nil || library.hasBooks {
            let server = library.server
            let search = shell.search
            VStack(alignment: .leading, spacing: 0) {
                SearchField(search: search)
                    .padding(.horizontal, SpreadMetrics.margin)
                    .padding(.bottom, 12)
                    .frame(width: spread.pages?.leftWidth, alignment: .leading)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // With several, each server says so in its own section.
                        if !library.hasSeveralServers {
                            VStack(alignment: .leading, spacing: 12) {
                                ConnectionBannerSlot()
                                if let server, !search.serverSearches {
                                    Text("\(server.name) doesn’t offer search. Showing books on your iPhone.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, SpreadMetrics.margin)
                            .frame(width: spread.pages?.leftWidth, alignment: .leading)
                        }
                        if search.searchText == nil {
                            SearchStart(search: search, source: server?.id ?? .files)
                        } else if library.hasSeveralServers {
                            SearchServerSections(search: search)
                        } else {
                            SearchResultsContent(search: search)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            // Held to the top left: a screen narrower than the spread
            // (only placeholders on the left page) would otherwise centre.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            NoLibraryInvitation()
        }
    }
}

/// A capsule like the system's search field, with a clear button once
/// something's typed. Opening a result puts the keyboard away and keeps the
/// search in Recent.
private struct SearchField: View {
    @Bindable var search: SearchModel
    @FocusState private var focused: Bool
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let covered = !shell[path: .search].routes.isEmpty
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $search.query, prompt: Text("Title, author, series"))
                .focused($focused)
                .submitLabel(.search)
                .onSubmit { search.submit() }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !search.query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    search.query = ""
                    focused = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(.tertiarySystemFill), in: .capsule)
        .onChange(of: covered) {
            guard covered else { return }
            focused = false
            search.remember()
        }
    }
}

/// Before typing: Recent, then Browse. Unfolded, Recent on the left page and
/// Browse on the right.
private struct SearchStart: View {
    let search: SearchModel
    let source: LibrarySourceID
    @Environment(\.spread) private var spread
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let hasRecent = !search.recentSearches.isEmpty
        if spread.pages != nil, hasRecent || library.hasSeveralServers {
            SpreadRow { page, _ in
                Group {
                    if hasRecent {
                        if page == 0 { recent } else { browse }
                    } else if page == 0 {
                        // Several servers, nothing recent: the first's lists
                        // on the left page, the others' on the right.
                        browseServers(library.connections.prefix(1))
                    } else {
                        browseServers(library.connections.dropFirst())
                    }
                }
                .padding(.horizontal, SpreadMetrics.margin)
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if hasRecent { recent }
                browse
            }
            .padding(.horizontal, SpreadMetrics.margin)
            .frame(width: spread.pages?.leftWidth, alignment: .leading)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SearchHeading("Recent")
                Spacer()
                Button("Clear") { search.clearRecentSearches() }
                    .accessibilityLabel("Clear recent searches")
            }
            ForEach(search.recentSearches, id: \.self) { text in
                Button {
                    search.query = text
                    search.submit()
                } label: {
                    Label(text, systemImage: "clock")
                        .labelStyle(RecentLabelStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var browse: some View {
        if library.hasSeveralServers {
            browseServers(library.connections[...])
        } else {
            BrowseLists(source: source)
        }
    }

    private func browseServers(_ connections: ArraySlice<ServerConnection>) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(connections, id: \.server.id) { connection in
                // Its own lists or none: another server's would open through
                // this one.
                BrowseLists(source: connection.server.id, title: "Browse \(connection.server.name)", chips: connection.root?.chips ?? [])
            }
        }
    }
}

private struct RecentLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .foregroundStyle(.secondary)
            configuration.title
                .lineLimit(1)
        }
    }
}

/// The library's own lists as chips (BookOrbit's All, Collections, Series
/// and Authors; an OPDS catalog's sections), each opening in this tab.
private struct BrowseLists: View {
    let source: LibrarySourceID
    var title = "Browse"
    /// `nil`: the Library's server's.
    var chips: [LibraryEntry]?
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let chips = chips ?? library.root?.chips, !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SearchHeading(title)
                ChipFlow(spacing: 8) {
                    ForEach(chips) { chip in
                        Button(chip.title) { shell.push(.feed(chip, from: source)) }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(.secondary)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
}

/// The results: Books, then Series and Authors. Unfolded, the books take
/// the left page and the series and authors the right; with neither, the
/// books flow down the left page and on down the right.
private struct SearchResultsContent: View {
    let search: SearchModel
    @Environment(\.spread) private var spread

    var body: some View {
        if let results = search.results {
            if search.state == .failed {
                failure(results.query)
            }
            if results.books.isEmpty, results.series.isEmpty, results.authors.isEmpty {
                if search.state == .loaded {
                    ContentUnavailableView.search(text: results.query)
                        .frame(width: spread.pages?.leftWidth)
                        .padding(.top, 40)
                }
            } else {
                // The last results stay as they are until the next arrive:
                // dimming them on every keystroke flickered.
                sections(results)
            }
        } else {
            placeholders
        }
    }

    @ViewBuilder
    private func sections(_ results: SearchModel.Results) -> some View {
        let books = Array(results.books.prefix(search.bookLimit))
        let hasEntries = !results.series.isEmpty || !results.authors.isEmpty
        if spread.pages != nil, hasEntries {
            SpreadRow { page, _ in
                Group {
                    if page == 0 {
                        if books.isEmpty { entries(results) } else { bookSection(books, results) }
                    } else if !books.isEmpty {
                        entries(results)
                    }
                }
                .padding(.horizontal, SpreadMetrics.margin)
            }
        } else if spread.pages != nil {
            VStack(alignment: .leading, spacing: 4) {
                SearchHeading("Books")
                    .padding(.horizontal, SpreadMetrics.margin)
                    .frame(width: spread.pages?.leftWidth, alignment: .leading)
                SpreadList(items: Self.flowing(books, all: results.allBooks)) { item in
                    switch item {
                    case .book(let book): SearchBookRow(book: book)
                    case .all(let entry): AllBooksLink(entry: entry, source: results.source)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                if !books.isEmpty { bookSection(books, results) }
                entries(results)
            }
            .padding(.horizontal, SpreadMetrics.margin)
        }
    }

    private func bookSection(_ books: [SourcedBook], _ results: SearchModel.Results) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SearchHeading("Books")
            ForEach(books) { book in
                SearchBookRow(book: book)
            }
            if let all = results.allBooks {
                AllBooksLink(entry: all, source: results.source)
            }
        }
    }

    @ViewBuilder
    private func entries(_ results: SearchModel.Results) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if !results.series.isEmpty {
                entrySection("Series", results.series, source: results.source)
            }
            if !results.authors.isEmpty {
                entrySection("Authors", results.authors, source: results.source)
            }
        }
    }

    private func entrySection(_ title: String, _ entries: [LibraryEntry], source: LibrarySourceID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchHeading(title)
                .padding(.bottom, 4)
            ForEach(entries) { entry in
                EntryRow(entry: entry, source: source)
                    .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private func failure(_ query: String) -> some View {
        HStack {
            Text("Couldn’t search for “\(query)”.")
                .foregroundStyle(.secondary)
            Button("Try again") { search.retry() }
        }
        .font(.subheadline)
        .padding(.horizontal, SpreadMetrics.margin)
        .frame(width: spread.pages?.leftWidth, alignment: .leading)
    }

    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 4) {
            SearchHeading("Books")
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                        .frame(width: 40, height: 60)
                    Text(verbatim: "A book’s title\nIts author")
                        .redacted(reason: .placeholder)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, SpreadMetrics.margin)
        .frame(width: spread.pages?.leftWidth, alignment: .leading)
        .accessibilityHidden(true)
    }

    enum FlowItem: Identifiable {
        case book(SourcedBook)
        case all(LibraryEntry)

        var id: String {
            switch self {
            case .book(let book): "book-\(book.source.rawValue)-\(book.book.id.rawValue)"
            case .all: "all"
            }
        }
    }

    static func flowing(_ books: [SourcedBook], all: LibraryEntry?) -> [FlowItem] {
        books.map(FlowItem.book) + (all.map { [FlowItem.all($0)] } ?? [])
    }
}

/// The results with several servers (decision 36): a section for each, one
/// per page unfolded, a third carrying on down the right page. Each fills in
/// when its server answers, so a slow one doesn't move the rest.
private struct SearchServerSections: View {
    let search: SearchModel
    @Environment(\.spread) private var spread

    var body: some View {
        if spread.pages != nil {
            SpreadRow { page, _ in
                column(page == 0 ? search.sections.prefix(1) : search.sections.dropFirst())
                    .padding(.horizontal, SpreadMetrics.margin)
            }
        } else {
            column(search.sections[...])
                .padding(.horizontal, SpreadMetrics.margin)
        }
    }

    private func column(_ sections: ArraySlice<SearchModel.Section>) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(sections) { section in
                SearchServerSection(search: search, section: section)
            }
        }
    }
}

/// One server's results: its name, its first books and "All 9 books", then
/// its series and authors. A server that can't answer says so here.
private struct SearchServerSection: View {
    let search: SearchModel
    let section: SearchModel.Section
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    private var connection: ServerConnection? {
        library.connection(section.source)
    }

    private var name: String {
        connection?.server.name ?? "On iPhone"
    }

    var body: some View {
        let results = section.results
        VStack(alignment: .leading, spacing: 4) {
            SearchHeading(name)
            message
            if let results {
                ForEach(results.books.prefix(search.bookLimit)) { book in
                    SearchBookRow(book: book)
                }
                if let all = results.allBooks {
                    AllBooksLink(entry: all, source: results.source)
                }
                entries("Series", results.series, source: results.source)
                entries("Authors", results.authors, source: results.source)
                if isEmpty(results), section.state == .loaded, connection?.problem == nil, connection?.root?.search != .unavailable {
                    Text("No results")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            } else if section.state == .searching {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.quaternary)
                            .frame(width: 40, height: 60)
                        Text(verbatim: "A book’s title\nIts author")
                            .redacted(reason: .placeholder)
                    }
                    .padding(.vertical, 6)
                    .accessibilityHidden(true)
                }
            }
        }
        // Its own height, not a share of the page's: titles keep their two
        // lines on the right page, which is narrower than one folded.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isEmpty(_ results: SearchModel.Results) -> Bool {
        results.books.isEmpty && results.series.isEmpty && results.authors.isEmpty
    }

    /// Why this server has nothing to show (decision 36).
    @ViewBuilder
    private var message: some View {
        switch connection?.problem {
        case .unreachable:
            sentence("Can’t reach \(name).", action: "Try again") { search.retry(section.source) }
        case .signedOut:
            sentence("Signed out of \(name).", action: "Sign in") { shell.showSignIn(section.source) }
        case nil:
            if section.state == .failed {
                sentence("Couldn’t search \(name).", action: "Try again") { search.retry(section.source) }
            } else if connection?.root?.search == .unavailable {
                sentence("\(name) doesn’t offer search.")
            }
        }
    }

    private func sentence(_ text: String, action: String? = nil, perform: @escaping () -> Void = {}) -> some View {
        HStack {
            Text(text)
                .foregroundStyle(.secondary)
            if let action {
                Button(action, action: perform)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func entries(_ title: String, _ entries: [LibraryEntry], source: LibrarySourceID) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                ForEach(entries) { entry in
                    EntryRow(entry: entry, source: source)
                        .padding(.vertical, 10)
                    Divider()
                }
            }
        }
    }
}

/// A book in the results: its cover (with the download mark), title,
/// author and your place in it.
private struct SearchBookRow: View {
    let book: SourcedBook
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let progress = shell.places.progress(of: book)
        OpenButton(route: .cover(book)) {
            HStack(spacing: 12) {
                BookCover(book: book, cornerRadius: 2)
                    .overlay(alignment: .bottomTrailing) { DownloadBadge(book: book, size: 14) }
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.book.title.isEmpty ? "Untitled" : book.book.title)
                        .lineLimit(2)
                    if !book.book.authors.isEmpty {
                        Text(book.book.authors.formatted(.list(type: .and)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let place = Self.place(book.book, progress: progress) {
                        Text(place)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
        // Where the book opens, as the server has it (`BookPlaces`).
        .onAppear { shell.places.refreshRow(book) }
    }

    /// "Finished", "42%", or nothing for a book not started.
    static func place(_ book: LibraryBook, progress: Double?) -> String? {
        if book.isFinished == true { return "Finished" }
        guard let progress, progress > 0 else { return nil }
        return BookPage.placeLine(progress: progress)
    }
}

/// "All 40 books": every match, as a Library list.
private struct AllBooksLink: View {
    let entry: LibraryEntry
    let source: LibrarySourceID

    var body: some View {
        ShellLink(.feed(entry, from: source), showsChevron: false) {
            Text(entry.count.map { "All \($0) books" } ?? "All books")
                .foregroundStyle(.tint)
                .padding(.vertical, 10)
        }
    }
}

private struct SearchHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Chips in rows, wrapping onto the next row when one is full.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(in width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let row = rows.count - 1
            rows[row].width += (rows[row].indices.isEmpty ? 0 : spacing) + size.width
            rows[row].height = max(rows[row].height, size.height)
            rows[row].indices.append(index)
        }
        return rows
    }
}
