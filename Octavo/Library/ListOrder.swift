import OctavoKit
import SwiftUI

// A list of books' Sort and Filter buttons, under Back in the side column
// (#131 step 2, `docs/notes/library-filters.md`). The source says what each
// list offers (`LibrarySource.order(of:)`); lists of series, authors and
// collections get neither.

extension LibrarySort {
    var title: String {
        switch self {
        case .readingOrder: "Reading order"
        case .title: "Title"
        case .author: "Author"
        case .recentlyAdded: "Recently added"
        case .recentlyDownloaded: "Recently downloaded"
        }
    }
}

extension LibraryFilter {
    /// In the menu.
    var title: String {
        switch self {
        case .all: "All books"
        case .unread: "Unread"
        case .reading: "Reading"
        case .finished: "Finished"
        }
    }
}

/// The sort last picked on each server's lists, remembered on the iPhone
/// (Adam, 2026-11-09). Only lists that take it open in it
/// (`LibraryListOrder.takesRememberedSort`): a series keeps its reading
/// order. The filter isn't remembered.
nonisolated enum SavedSorts {
    static let key = "library.sorts"

    static func sort(for server: LibrarySourceID, in defaults: UserDefaults = .standard) -> LibrarySort? {
        (defaults.dictionary(forKey: key)?[server.rawValue] as? String).flatMap(LibrarySort.init(rawValue:))
    }

    static func remember(_ sort: LibrarySort, for server: LibrarySourceID, in defaults: UserDefaults = .standard) {
        var sorts = defaults.dictionary(forKey: key) ?? [:]
        sorts[server.rawValue] = sort.rawValue
        defaults.set(sorts, forKey: key)
    }

    /// Remove server.
    static func forget(_ server: LibrarySourceID, in defaults: UserDefaults = .standard) {
        guard var sorts = defaults.dictionary(forKey: key) else { return }
        sorts[server.rawValue] = nil
        defaults.set(sorts, forKey: key)
    }

    /// The list at `link` as it opens: in the sort remembered for `server`,
    /// if it takes one and offers it.
    static func opening(_ link: LibraryLink, from library: any LibrarySource, server: LibrarySourceID, in defaults: UserDefaults = .standard) -> LibraryLink {
        guard let order = library.order(of: link), order.takesRememberedSort,
              let sort = sort(for: server, in: defaults), sort != order.sort, order.sorts.contains(sort) else { return link }
        return library.link(link, sortedBy: sort, showing: order.filter)
    }
}

/// Sort and Filter, as the side column's buttons on the Duo and the bar's
/// elsewhere. Only Filter fills, while it hides books.
struct ListOrderButtons: ToolbarContent {
    let order: LibraryListOrder
    let pick: (LibrarySort?, LibraryFilter) -> Void

    var body: some ToolbarContent {
        if !order.sorts.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: Binding { order.sort } set: { pick($0, order.filter) }) {
                        ForEach(order.sorts, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityValue(order.sort?.title ?? "")
            }
        }
        if !order.filters.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                if order.filter == .all {
                    filterMenu
                } else {
                    filterMenu
                        .menuStyle(.button)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: Binding { order.filter } set: { pick(order.sort, $0) }) {
                ForEach(order.filters, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityValue(order.filter.title)
    }
}

/// While a list is filtered, its title is what's shown ("Unread"; Adam,
/// 2026-11-09). Otherwise the route's.
struct FilteredTitle: ViewModifier {
    let filter: LibraryFilter?

    func body(content: Content) -> some View {
        if let filter, filter != .all {
            content.navigationTitle(filter.title)
        } else {
            content
        }
    }
}

/// On iPhone's Sort and Filter (#131): Title, Author or Recently downloaded
/// (Books on iPhone's own orders), remembered on the iPhone, and each
/// book's status from Octavo's own record (`ShellModel.status(of:)`).
nonisolated enum OnIPhoneOrder {
    static let sortKey = "library.onIPhone.sort"
    static let sorts: [LibrarySort] = [.title, .author, .recentlyDownloaded]

    static func order(_ sort: LibrarySort, _ filter: LibraryFilter) -> LibraryListOrder {
        LibraryListOrder(
            sorts: sorts, filters: LibraryFilter.allCases, sort: sorts.contains(sort) ? sort : .title, filter: filter,
            takesRememberedSort: false
        )
    }

    /// Books on iPhone's own orders (`DownloadOrder`).
    static func sorted(_ books: [DownloadedBook], by sort: LibrarySort) -> [DownloadedBook] {
        let order: DownloadOrder = switch sort {
        case .author: .author
        case .recentlyDownloaded: .downloaded
        case .title, .readingOrder, .recentlyAdded: .title
        }
        return order.sorted(books)
    }
}
