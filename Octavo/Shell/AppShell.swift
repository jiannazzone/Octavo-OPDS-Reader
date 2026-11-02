import SwiftUI

/// The app's root: three tabs in the side column (Home, Library, Search),
/// each a `ScreenStack` whose top screen fills the spread, and the reader
/// over them when a book is open.
///
/// The reader is a layer over the tabs, not a `fullScreenCover`: a cover
/// presented by an unfold (which starts about 200 ms before the scene moves
/// to the inner display) stays laid out for the outer display, turned on
/// its side (`docs/notes/duo-tabbar.md` §6). A layer in the same hierarchy
/// follows the scene like any other view.
///
/// No pop-up alerts anywhere, except to confirm deleting or removing
/// something. Problems show as a `ConnectionBanner` at the top of a screen,
/// a `CoverStripMessage` on a book's screen, or an `EmptyInvitation` on an
/// empty screen; sign-in errors sit under the fields.
struct AppShell: View {
    @State private var model = ShellModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if model.needsSetup {
                    // No tabs, and nothing to skip to (decision 6).
                    ScreenStack(tab: .setup, title: "Add your books", showsSettings: false) {
                        SetupStart()
                    }
                } else {
                    tabs
                }
            }
            .accessibilityHidden(isCovered)
            if let book = model.reading {
                ReaderView(
                    book: book, bookmarkSync: model.readingBookmarkSync,
                    progressSync: model.readingProgressSync, listedPlace: model.readingListedPlace,
                    connectionReturns: model.connection.returns
                ) { model.reading = nil }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.retryUnsentPlaces() }
        }
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
        TabView(selection: Binding(get: { model.tab }, set: { model.select($0) })) {
            Tab("Home", systemImage: "house", value: .home) {
                ScreenStack(tab: .home, title: "Home") { HomeView() }
            }
            Tab("Library", systemImage: "books.vertical", value: .library) {
                ScreenStack(tab: .library, title: "Library") { LibraryView() }
            }
            Tab(value: .search, role: .search) {
                ScreenStack(tab: .search, title: "Search") { SearchView() }
            }
        }
    }
}

#Preview {
    AppShell()
}
