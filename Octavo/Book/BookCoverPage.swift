import OctavoKit
import SwiftUI

/// A book's cover page (decisions 4, 5 and 20; frames 03, 04, 15 and 16):
/// the cover filling the screen, with a glass sheet at the bottom that
/// expands into the details.
///
/// - Folded, the cover runs under the side column and the camera. Unfolded
///   it fills the pane right of the hinge, and the sheet stays in that pane.
/// - Nothing is drawn behind the side column: the system's own glass
///   capsules (clock, Back, tabs) read on any cover (Adam, 2026-11-01).
/// - Unfolding on this page opens the book (`ShellModel.hingeChanged`).
/// - Tapping the cover while the details show returns to the strip.
struct BookCoverPage: View {
    let book: LibraryBook
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell
    @Environment(\.pane) private var pane

    var body: some View {
        let page = shell.pages.page(for: book)
        ZStack(alignment: .bottom) {
            BookCoverArt(page: page)
                // Folded the cover runs under the side column (decision 4);
                // unfolded it stops at the column, as in frame 16.
                .ignoresSafeArea(edges: pane.level == nil ? .all : .vertical)
                .onTapGesture {
                    guard page.isExpanded else { return }
                    withAnimation(BookSheet.animation) { page.isExpanded = false }
                }
            // 8 pt from the bottom edge, as in frame 03.
            BookSheet(page: page, source: source)
                .padding(8)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear {
            page.load(from: source)
            shell.opener.clearFailure(book)
            shell.opener.coverAppeared(book, from: source)
        }
    }
}

/// The cover image, filling its space and cropped to it. Before it loads,
/// a plain background; a book without a cover shows its title.
struct BookCoverArt: View {
    let page: BookPage

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let cover = page.cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if page.coverFinished {
                    BookTitleCover(title: page.current.title, author: page.authorLine)
                }
            }
            .clipped()
            .animation(.easeOut(duration: 0.2), value: page.cover)
            .accessibilityElement()
            .accessibilityLabel(page.current.title.isEmpty ? "Cover" : "Cover of \(page.current.title)")
    }
}

/// For a book without cover artwork: its title and author on a quiet
/// background.
struct BookTitleCover: View {
    let title: String
    let author: String

    var body: some View {
        LinearGradient(colors: [Color(white: 0.32), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
            .overlay {
                VStack(spacing: 8) {
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(.system(.largeTitle, design: .serif).bold())
                    Text(author)
                        .font(.system(.title3, design: .serif))
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(40)
                .minimumScaleFactor(0.3)
            }
    }
}

#if DEBUG
#Preview("Cover page") {
    let shell = ShellModel()
    NavigationStack {
        BookCoverPage(book: SampleLibrarySource.books[0], source: SampleLibrarySource())
    }
    .environment(shell)
}
#endif
