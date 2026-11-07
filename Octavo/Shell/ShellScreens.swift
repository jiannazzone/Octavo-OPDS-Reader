import OctavoKit
import SwiftUI

// The route-to-screen map, a book's screen from its library, and the
// connection banner.

/// The view for a route.
struct ShellScreen: View {
    let route: ShellRoute

    var body: some View {
        switch route {
        case .feed(let entry, let source): FeedScreen(entry: entry, source: source)
        case .settings: SettingsScreen(page: nil)
        case .settingsPage(let page): SettingsScreen(page: page)
        case .cover(let book): CoverScreen(book: book)
        case .setup(let step): SetupScreen(step: step)
        case .signInAgain(let id): SignInAgainScreen(server: id)
        case .onIPhone: OnIPhoneScreen()
        }
    }
}

/// A book's screen, from the library the book came from. Its author opens
/// their books on top of it, and Open goes through the shell so the book
/// joins Home's Continue reading.
struct CoverScreen: View {
    let book: SourcedBook
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let source = library.source(for: book.source) {
            BookCoverPage(book: book.book, sourceID: book.source, source: source)
                .id(library.connection)
                .environment(\.openLibraryEntry) { entry in
                    shell.push(.feed(entry, from: book.source))
                }
                .environment(\.openBook) { opened in
                    shell.reader.open(SourcedBook(source: book.source, book: opened))
                }
                .environment(\.downloadBook) { downloading in
                    shell.downloadBook(SourcedBook(source: book.source, book: downloading))
                }
        } else {
            LibraryNotConnected()
        }
    }
}

/// The Library's server's banner, when there's a problem.
struct ConnectionBannerSlot: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        if let id = library.server?.id, let problem = library.connectionProblem {
            ServerProblemBanner(server: id, problem: problem)
        }
    }
}

/// Home's banners, one per server: `LibraryModel.homeProblems`.
struct HomeBannersSlot: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        ForEach(library.homeProblems, id: \.server) { item in
            ServerProblemBanner(server: item.server, problem: item.problem)
        }
    }
}

/// A server's banner, whose action is for that server.
private struct ServerProblemBanner: View {
    let server: LibrarySourceID
    let problem: ConnectionProblem
    @Environment(LibraryModel.self) private var library
    @Environment(ShellModel.self) private var shell

    var body: some View {
        ConnectionBanner(problem: problem) {
            switch problem {
            case .unreachable:
                Task { await library.retry(server) }
            case .signedOut:
                shell.showSignIn(server)
            }
        }
    }
}
