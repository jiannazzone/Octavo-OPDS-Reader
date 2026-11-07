import SwiftUI

/// How a screen lays out on the Duo: one page folded, two pages unfolded or
/// half open. Every screen is a spread: its content flows from the left page
/// onto the right, and nothing sits on the hinge (`docs/design/direction.md`).
///
/// The pages split where the hinge's division region runs. On the Duo's inner
/// display a tab's content is 867 pt wide (the side column takes the rest)
/// and the region is x 455.5–495.5, active when half open and inactive when
/// flat. Both split the same way, so this reads only the geometry, not the
/// hinge's status: folded there is no region, and no other iPhone reports
/// one.
nonisolated struct Spread: Equatable, Sendable {
    nonisolated struct Pages: Equatable, Sendable {
        var leftWidth: CGFloat
        var hingeWidth: CGFloat
        var rightWidth: CGFloat
    }

    var width: CGFloat
    /// `nil`: one page.
    var pages: Pages?

    var isTwoPages: Bool { pages != nil }

    /// A side narrower than this isn't worth a page.
    static let minimumPageWidth: CGFloat = 200

    static let onePage = Spread(width: 0, pages: nil)

    init(width: CGFloat, pages: Pages?) {
        self.width = width
        self.pages = pages
    }

    /// Two pages only if a division region runs top to bottom through a view
    /// `width` wide, in the view's leading-to-trailing coordinates, with room
    /// for a page each side. That also rules out the transients around a
    /// fold: a region turned across the view, or one reported while the view
    /// still has the outer display's width (`docs/notes/duo-spreads.md` §1).
    init(width: CGFloat, divisions: [CGRect]) {
        self.width = width
        if let hinge = divisions.first(where: { $0.height > $0.width }),
           hinge.minX >= Self.minimumPageWidth,
           width - hinge.maxX >= Self.minimumPageWidth {
            pages = Pages(leftWidth: hinge.minX, hingeWidth: hinge.width, rightWidth: width - hinge.maxX)
        } else {
            pages = nil
        }
    }

    init(_ proxy: GeometryProxy) {
        self.init(
            width: proxy.size.width,
            divisions: proxy.reservedRegions(kind: .division, options: .includeInactive).map(\.frame)
        )
    }
}

extension EnvironmentValues {
    @Entry var spread = Spread.onePage
}

extension View {
    /// Reads the spread of the space this view is offered. The view takes
    /// exactly that width (`maxWidth` alone grows with what's inside): its
    /// pages take fixed widths from the spread, so a view as wide as its
    /// pages kept a wrong reading (the inner display's full width, without
    /// the side column) for good (`docs/notes/duo-tabbar.md` §7). Pages
    /// still too wide for a moment hang off the trailing edge, so the left
    /// page stays put.
    func onSpreadChange(_ action: @escaping (Spread) -> Void) -> some View {
        frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: Spread.self) { Spread($0) } action: { action($0) }
    }
}
