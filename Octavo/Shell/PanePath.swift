import Foundation

/// One tab's navigation: the screens opened from its root, in order.
///
/// Level 0 is the tab's root and level n is `routes[n - 1]`. Folded, the
/// deepest level shows. Unfolded or half open, two adjacent levels show,
/// left and right of the hinge (decision 23): opening a screen from the left
/// pane replaces the right one, opening one from the right pane shifts both
/// panes one level along, and Back shifts them back. With nothing open, the
/// right pane shows the root's `companion`, such as Home's current book
/// (decision 26) or the server page beside Settings.
nonisolated struct PanePath: Hashable, Sendable {
    var routes: [ShellRoute] = []
    var companion: ShellRoute?

    /// The screen at `level`; `nil` for the root and past the end.
    func route(at level: Int) -> ShellRoute? {
        level >= 1 && level <= routes.count ? routes[level - 1] : nil
    }

    /// Opens `route` from the screen at `level`, closing anything deeper.
    /// Opening from the companion keeps it, one level in.
    mutating func open(_ route: ShellRoute, from level: Int) {
        var kept = Array(routes.prefix(max(level, 0)))
        if level == 1, kept.isEmpty, let companion {
            kept = [companion]
        }
        routes = kept + [route]
    }

    // MARK: Unfolded

    /// The right pane of the pair whose left pane shows `level`.
    func rightOfPair(_ level: Int) -> ShellRoute? {
        route(at: level + 1) ?? (level == 0 ? companion : nil)
    }

    /// The pairs above the root pair on the unfolded `NavigationStack`, by
    /// their left pane's level: routes [a, b, c] show root | a, a | b, b | c.
    /// The stack only ever pops them (Back, swipe), which closes the deepest
    /// screens.
    var pushedPairs: [PaneLevel] {
        get { routes.count >= 2 ? (1..<routes.count).map(PaneLevel.init) : [] }
        set {
            guard newValue.count < pushedPairs.count else { return }
            routes = Array(routes.prefix(newValue.count + 1))
        }
    }
}

/// A pair of panes on the unfolded stack, named by its left pane's level.
nonisolated struct PaneLevel: Hashable, Sendable {
    var value: Int
}
