import SwiftUI

/// Where a screen splits at the hinge: the left pane ends where the hinge's
/// division region starts and the right pane starts where it ends, so
/// nothing sits on the hinge (decision 9).
///
/// On the Duo's inner display a tab's content is 867 pt wide (the side
/// column takes the rest) and the region is x 455.5–495.5, active when half
/// open and inactive when flat. Both split the same way, so this reads only
/// the geometry, not the hinge's status: folded there is no region, and no
/// other iPhone reports one.
nonisolated struct PaneSplit: Equatable, Sendable {
    var leftWidth: CGFloat
    var hingeWidth: CGFloat
    var rightWidth: CGFloat

    /// A side narrower than this isn't worth a pane.
    static let minimumPaneWidth: CGFloat = 200

    /// `nil` (one pane) unless a division region runs top to bottom through
    /// a view `width` wide, in the view's leading-to-trailing coordinates,
    /// with room for a pane each side. That also rules out the transients
    /// around a fold: a region turned across the view, or one reported while
    /// the view still has the outer display's width (`docs/notes/duo-spreads.md` §1).
    init?(width: CGFloat, divisions: [CGRect]) {
        guard let hinge = divisions.first(where: { $0.height > $0.width }),
              hinge.minX >= Self.minimumPaneWidth,
              width - hinge.maxX >= Self.minimumPaneWidth
        else { return nil }
        leftWidth = hinge.minX
        hingeWidth = hinge.width
        rightWidth = width - hinge.maxX
    }

    init?(_ proxy: GeometryProxy) {
        self.init(
            width: proxy.size.width,
            divisions: proxy.reservedRegions(kind: .division, options: .includeInactive).map(\.frame)
        )
    }
}
