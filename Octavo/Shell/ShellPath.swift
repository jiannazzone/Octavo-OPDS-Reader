import Foundation

/// One tab's screens, in order, under the tab's list (`TabSplit`): the pick
/// in the right column, then what's pushed over it. Folded, they're the
/// system's stack over the list.
nonisolated struct ShellPath: Hashable, Sendable {
    private(set) var routes: [ShellRoute] = []

    /// The screen on top; `nil` at the tab's list.
    var top: ShellRoute? { routes.last }

    mutating func push(_ route: ShellRoute) {
        routes.append(route)
    }

    mutating func pop() {
        guard !routes.isEmpty else { return }
        routes.removeLast()
    }

    mutating func popToRoot() {
        routes = []
    }

    /// Sets the whole stack: a new server, a chip, debug launch arguments.
    mutating func replace(_ routes: [ShellRoute]) {
        self.routes = routes
    }

    /// What's picked in the tab's list: the right column's first screen.
    var pick: ShellRoute? { routes.first }

    /// The screens pushed in the right column, over its pick.
    var pushed: [ShellRoute] { Array(routes.dropFirst()) }

    /// Picks `route` in the list, in place of whatever the right column
    /// showed; `nil` goes back to the list (folded, Back from the pick).
    /// Picking what's picked goes back to it, over whatever was pushed.
    mutating func pick(_ route: ShellRoute?) {
        routes = route.map { [$0] } ?? []
    }

    /// The right column's stack after Back or a swipe there.
    mutating func setPushed(_ pushed: [ShellRoute]) {
        guard let pick else { return }
        routes = [pick] + pushed
    }
}
