import SwiftUI

/// The app's root: four tabs in the side column (decision 2), each a
/// `PaneStack` that splits at the hinge when unfolded or half open, and the
/// reader over them when a book is open.
///
/// The reader is a layer over the tabs, not a `fullScreenCover`: a cover
/// presented by an unfold (which starts about 200 ms before the scene moves
/// to the inner display) stays laid out for the outer display, turned on
/// its side (`docs/notes/duo-tabbar.md` §6). A layer in the same hierarchy
/// follows the scene like any other view.
///
/// No pop-up alerts anywhere, except to confirm deleting or removing
/// something (decision 22). Problems show as a `ConnectionBanner` at the top
/// of a tab, a `CoverStripMessage` on a book's cover, or an
/// `EmptyInvitation` on an empty screen; sign-in errors sit under the fields.
struct AppShell: View {
    @State private var model = ShellModel()

    var body: some View {
        ZStack {
            tabs
                .accessibilityHidden(isCovered)
            if let book = model.reading {
                ReaderView(book: book) { model.reading = nil }
                    // Another book is another reader: its own model, hooks
                    // and controls, and the old one closes (flushing its
                    // position).
                    .id(book.reader)
                    // Fades in, but leaves at once: a reader still fading
                    // out keeps its web page attached, and an unfold
                    // meanwhile has SwiftUI rebuild that web view, which
                    // WebKit traps on (open, close, open again, unfold).
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .onHingeChange { old, new in
            model.hingeChanged(HingeTransition(from: old, to: new))
        }
        .animation(.default, value: model.reading)
        .environment(model)
        .environment(model.library)
        #if DEBUG
        .task { await ReaderRemote.run(shell: model) }
        .debugProbe("shell")
        #endif
    }

    private var isCovered: Bool {
        model.reading != nil
    }

    private var tabs: some View {
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "house", value: .home) {
                PaneStack(tab: .home, title: "Home", path: $model[path: .home], background: Color(.systemBackground)) { HomeView() }
            }
            Tab("Library", systemImage: "books.vertical", value: .library) {
                PaneStack(tab: .library, title: "Library", path: $model[path: .library], background: Color(.systemBackground)) {
                    LibraryView()
                }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                PaneStack(tab: .settings, title: "Settings", path: $model[path: .settings]) { SettingsPlaceholder() }
            }
            Tab(value: .search, role: .search) {
                PaneStack(tab: .search, title: "Search", path: $model[path: .search]) { SearchPlaceholder() }
            }
        }
    }
}

#Preview {
    AppShell()
}
