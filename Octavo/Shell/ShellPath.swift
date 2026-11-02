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

    /// Back from Settings unfolded: its page and its list go together.
    mutating func pop(_ count: Int) {
        guard count > 0, !routes.isEmpty else { return }
        routes.removeLast(min(count, routes.count))
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
}
