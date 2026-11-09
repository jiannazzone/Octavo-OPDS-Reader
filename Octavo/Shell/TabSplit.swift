import SwiftUI

/// Settings' split, in its sheet (`SettingsSheet`): its list on the left and
/// the chosen page on the right, where further screens push. Compact (the
/// open Duo's sheet, an iPhone) it collapses to one stack with the system's
/// Back and swipe. Its state is a `ShellPath`: the pick, then what's pushed
/// over it.
///
/// - The list is a `List` whose selection is the pick
///   (`ShellModel.pickBinding`): that's what gives the collapsed stack its
///   Back. A list in a plain scroll view collapses with none.
/// - With two columns and nothing picked, the right column shows
///   `ShellModel.defaultPick` (the server's page) without picking it.
struct TabSplit<Menu: View, Buttons: ToolbarContent>: View {
    let tab: ShellTab
    @ViewBuilder let menu: () -> Menu
    /// On the list, in both postures (Settings' close).
    @ToolbarContentBuilder let buttons: () -> Buttons
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            menu()
                .measuresSpread()
                .toolbar { buttons() }
        } detail: {
            NavigationStack(path: pushed) {
                Group {
                    if let pick = shell[path: tab].pick ?? shell.defaultPick(tab) {
                        // Another pick is another screen, not this one with
                        // the last one's state.
                        screen(pick)
                            .id(pick)
                    } else {
                        ContentUnavailableView("No Book Selected", systemImage: "books.vertical")
                    }
                }
                .navigationDestination(for: ShellRoute.self) { screen($0) }
            }
        }
        .onChange(of: sizeClass, initial: true) {
            if sizeClass == .compact {
                shell.expandedSplits.remove(tab)
            } else {
                shell.expandedSplits.insert(tab)
            }
        }
    }

    private func screen(_ route: ShellRoute) -> some View {
        ShellScreen(route: route)
            .measuresSpread()
            .routeTitle(route.title)
    }

    /// The right column's stack over the pick, which Back and the swipe
    /// there change.
    private var pushed: Binding<[ShellRoute]> {
        Binding { shell[path: tab].pushed } set: { shell[path: tab].setPushed($0) }
    }
}

extension ShellModel {
    /// What a split's `List` selects: `tab`'s pick.
    func pickBinding(_ tab: ShellTab) -> Binding<ShellRoute?> {
        Binding { self[path: tab].pick } set: { self.pick($0, in: tab) }
    }
}
