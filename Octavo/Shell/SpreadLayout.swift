import SwiftUI

// Building blocks for screens laid out as a spread: content on the left page
// and the right page, nothing on the hinge, and one page folded.

extension Spread {
    /// The pages' widths in reading order: one folded, two unfolded. Empty
    /// until the spread has been measured.
    var pageWidths: [CGFloat] {
        if let pages { return [pages.leftWidth, pages.rightWidth] }
        return width > 0 ? [width] : []
    }

    var hingeWidth: CGFloat { pages?.hingeWidth ?? 0 }
}

/// The page margin and the grid's sizes, shared by the spread's layouts.
enum SpreadMetrics {
    static let margin: CGFloat = 20
    static let spacing: CGFloat = 12
    static let minimumCell: CGFloat = 92
    /// Where a screen's title starts: level with the large title the system
    /// drew folded, so it doesn't jump when the Duo unfolds (measured in #13).
    static let titleTop: CGFloat = 30

    static func columns(_ page: CGFloat) -> Int {
        max(1, Int((page - 2 * margin + spacing) / (minimumCell + spacing)))
    }

    static func cellWidth(page: CGFloat, columns: Int) -> CGFloat {
        (page - 2 * margin - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }
}

/// A screen as a spread: unfolded, `left` on the left page and `right` on
/// the right, each given its page's width, and nothing on the hinge. Folded,
/// either the screen's own layout (`folded`) or one of the two pages, which
/// then keeps its place in the view across a fold, so the fold doesn't
/// start it again (Settings: a name half typed).
struct SpreadPages<Left: View, Right: View, Folded: View>: View {
    /// What shows folded.
    enum FoldedPage {
        case left, right, own
    }

    var alignment: VerticalAlignment = .center
    private let foldedPage: FoldedPage
    @ViewBuilder private let left: (_ width: CGFloat) -> Left
    @ViewBuilder private let right: (_ width: CGFloat) -> Right
    @ViewBuilder private let folded: () -> Folded
    @Environment(\.spread) private var spread

    /// Folded, the screen lays itself out its own way (`folded`).
    init(
        alignment: VerticalAlignment = .center,
        @ViewBuilder left: @escaping (_ width: CGFloat) -> Left,
        @ViewBuilder right: @escaping (_ width: CGFloat) -> Right,
        @ViewBuilder folded: @escaping () -> Folded
    ) {
        self.alignment = alignment
        foldedPage = .own
        self.left = left
        self.right = right
        self.folded = folded
    }

    var body: some View {
        let pages = spread.pages
        if pages == nil, foldedPage == .own {
            folded()
        } else {
            // One stack in both postures, so a page shown either way keeps
            // its place in it.
            HStack(alignment: alignment, spacing: 0) {
                if pages != nil || foldedPage == .left {
                    left(pages?.leftWidth ?? spread.width)
                        .frame(width: pages?.leftWidth)
                }
                if let pages {
                    Color.clear
                        .frame(width: pages.hingeWidth, height: 1)
                }
                if pages != nil || foldedPage == .right {
                    right(pages?.rightWidth ?? spread.width)
                        .frame(width: pages?.rightWidth)
                }
            }
        }
    }
}

extension SpreadPages where Folded == EmptyView {
    /// Folded, one of the two pages fills the screen.
    init(
        alignment: VerticalAlignment = .center, folded page: FoldedPage,
        @ViewBuilder left: @escaping (_ width: CGFloat) -> Left,
        @ViewBuilder right: @escaping (_ width: CGFloat) -> Right
    ) {
        self.alignment = alignment
        foldedPage = page
        self.left = left
        self.right = right
        folded = { EmptyView() }
    }
}

extension View {
    /// Unfolded, keeps the view to the left page's width (a screen's title,
    /// a banner, a heading); folded, the whole page.
    func onLeftPage(alignment: Alignment = .leading) -> some View {
        modifier(OnLeftPage(alignment: alignment))
    }
}

private struct OnLeftPage: ViewModifier {
    let alignment: Alignment
    @Environment(\.spread) private var spread

    func body(content: Content) -> some View {
        content.frame(width: spread.pages?.leftWidth, alignment: alignment)
    }
}

/// One row across the spread: a part on each page, the hinge left empty.
struct SpreadRow<Page: View>: View {
    @ViewBuilder let page: (_ index: Int, _ width: CGFloat) -> Page
    @Environment(\.spread) private var spread

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(spread.pageWidths.enumerated()), id: \.offset) { index, width in
                if index > 0 {
                    Color.clear.frame(width: spread.hingeWidth)
                }
                // Holds the page's width even when it has nothing on it.
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: width, height: 0)
                    page(index, width)
                }
                .frame(width: width, alignment: .topLeading)
            }
        }
    }
}

/// Covers in a grid that runs across both pages: as many columns as fit on
/// each page, all the same size, and rows that read left page then right.
/// Folded, the one page's columns.
struct SpreadGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    /// A shelf shows one row; `nil` shows them all.
    var maxRows: Int? = nil
    var onLastRowAppear: () -> Void = {}
    @ViewBuilder let cell: (Item) -> Cell
    @Environment(\.spread) private var spread

    var body: some View {
        let widths = spread.pageWidths
        let counts = widths.map(Self.columns)
        let perRow = max(counts.reduce(0, +), 1)
        // The same size on both pages: the smaller of the two fits either.
        let cellWidth = zip(widths, counts).map { Self.cellWidth(page: $0, columns: $1) }.min() ?? SpreadMetrics.minimumCell
        let allRows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        let rows = maxRows.map { Array(allRows.prefix($0)) } ?? allRows
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(rows.indices, id: \.self) { row in
                SpreadRow { page, _ in
                    HStack(alignment: .top, spacing: SpreadMetrics.spacing) {
                        ForEach(Self.items(in: rows, row: row, page: page, counts: counts)) { item in
                            cell(item)
                                .frame(width: cellWidth)
                        }
                    }
                    .padding(.horizontal, SpreadMetrics.margin)
                }
                .onAppear {
                    if row == rows.count - 1 { onLastRowAppear() }
                }
            }
        }
    }

    private static func columns(_ page: CGFloat) -> Int {
        SpreadMetrics.columns(page)
    }

    /// The items of `row` on `page`. Across a fold the row's pages can be
    /// laid out for the new spread before this grid is (a grid that goes
    /// from two rows folded to one unfolded asked for row 1 of 1, or page 1
    /// of one page, and trapped), so an index that's gone is no items.
    static func items(in rows: [[Item]], row: Int, page: Int, counts: [Int]) -> [Item] {
        guard rows.indices.contains(row), counts.indices.contains(page) else { return [] }
        let start = counts.prefix(page).reduce(0, +)
        return Array(rows[row].dropFirst(start).prefix(counts[page]))
    }

    private static func cellWidth(page: CGFloat, columns: Int) -> CGFloat {
        SpreadMetrics.cellWidth(page: page, columns: columns)
    }
}

/// A list that flows like a book's index: down the left page, then on down
/// the right one. Folded, one column.
struct SpreadList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row
    @Environment(\.spread) private var spread

    var body: some View {
        let pages = Self.split(items, into: spread.pageWidths.count)
        SpreadRow { page, _ in
            LazyVStack(alignment: .leading, spacing: 0) {
                if page < pages.count {
                    ForEach(pages[page]) { item in
                        row(item)
                    }
                }
            }
            .padding(.horizontal, SpreadMetrics.margin)
        }
    }

    /// The left page takes the first half, rounded up.
    static func split(_ items: [Item], into pages: Int) -> [[Item]] {
        guard pages > 1 else { return [items] }
        let half = (items.count + 1) / 2
        return [Array(items.prefix(half)), Array(items.dropFirst(half))]
    }
}
