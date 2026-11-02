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
                    let start = counts.prefix(page).reduce(0, +)
                    HStack(alignment: .top, spacing: SpreadMetrics.spacing) {
                        ForEach(rows[row].dropFirst(start).prefix(counts[page])) { item in
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
