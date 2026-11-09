import Foundation

/// One tab's screens: its root, then the screens opened from it, in order.
/// The deepest one fills the spread, folded or unfolded; there is one stack,
/// and a fold only lays its top screen out again.
nonisolated struct ShellPath: Hashable, Sendable {
    /// How the stack last changed, which picks the animation: a pushed
    /// screen slides in from the trailing edge, a popped one slides out.
    nonisolated enum Move: Hashable, Sendable {
        case push, pop, replace
    }

    private(set) var routes: [ShellRoute] = []
    private(set) var lastMove = Move.replace

    /// The screen on top; `nil` at the tab's root.
    var top: ShellRoute? { routes.last }

    mutating func push(_ route: ShellRoute) {
        routes.append(route)
        lastMove = .push
    }

    mutating func pop() {
        guard !routes.isEmpty else { return }
        routes.removeLast()
        lastMove = .pop
    }

    /// Opens `route` on top. On two pages, a route with a `leftPage` that's
    /// already showing goes beside it at once, in place of any page there.
    mutating func open(_ route: ShellRoute, twoPages: Bool) {
        guard twoPages, let left = route.leftPage else { return push(route) }
        var beneath = routes
        if beneath.last?.leftPage == left { beneath.removeLast() }
        guard beneath.last == left else { return push(route) }
        replace(beneath + [route])
    }

    /// On two pages, whether the screen at `depth` (the tab's root is 0) is
    /// drawn by the one above it, as its `leftPage`: its own screen stays out
    /// of sight, as Back leaves both.
    func isDrawnByTheOneAbove(_ depth: Int, twoPages: Bool) -> Bool {
        guard twoPages, depth > 0, depth < routes.count else { return false }
        return routes[depth].leftPage == routes[depth - 1]
    }

    /// Back, or a swipe from the edge. On two pages a route and its
    /// `leftPage` are one screen, so they go together.
    mutating func back(twoPages: Bool) {
        guard twoPages, let left = top?.leftPage, routes.dropLast().last == left else { return pop() }
        routes.removeLast(2)
        lastMove = .pop
    }

    mutating func popToRoot() {
        guard !routes.isEmpty else { return }
        routes = []
        lastMove = .pop
    }

    /// Sets the whole stack without an animation: a new server, a chip,
    /// debug launch arguments.
    mutating func replace(_ routes: [ShellRoute]) {
        self.routes = routes
        lastMove = .replace
    }

    // MARK: In a split (`TabSplit`)

    /// What's picked in the tab's list: the right column's first screen.
    var pick: ShellRoute? { routes.first }

    /// The screens pushed in the right column, over its pick.
    var pushed: [ShellRoute] { Array(routes.dropFirst()) }

    /// Picks `route` in the list, in place of whatever the right column
    /// showed; `nil` goes back to the list (folded, Back from the pick).
    /// Picking what's picked goes back to it, over whatever was pushed.
    mutating func pick(_ route: ShellRoute?) {
        if let route, route == pick {
            guard !pushed.isEmpty else { return }
            routes = [route]
            lastMove = .pop
            return
        }
        replace(route.map { [$0] } ?? [])
    }

    /// The right column's stack after Back or a swipe there.
    mutating func setPushed(_ pushed: [ShellRoute]) {
        guard let pick else { return }
        lastMove = pushed.count > self.pushed.count ? .push : .pop
        routes = [pick] + pushed
    }
}
