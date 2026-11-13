import OctavoKit
import SwiftUI

/// More (…) on a BookOrbit book (Adam, 2026-11-12): the other read statuses
/// BookOrbit keeps, with a tick on the book's (#120,
/// `docs/notes/book-status.md`). Folded it sits beside Mark finished;
/// unfolded, beside the title, where Mark finished and Open fill the row.
struct BookMoreButton: View {
    let page: BookPage
    let source: any LibrarySource
    /// As tall as the row's other buttons, in a row that fixes its height.
    var fillsHeight = false
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Menu {
            Picker("Status", selection: status) {
                ForEach(LibraryReadStatus.menu, id: \.self) { status in
                    Label(status.title, systemImage: status.symbol).tag(Optional(status))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .bookRoundLabel(fillsHeight: fillsHeight)
        }
        .bookRoundButton()
    }

    private var status: Binding<LibraryReadStatus?> {
        Binding {
            LibraryReadStatus.ticked(page.readStatus)
        } set: { status in
            guard let status, status != LibraryReadStatus.ticked(page.readStatus) else { return }
            Task {
                await page.setStatus(status, from: source)
                // Filters and Home follow (`LibraryModel.markedStatus`).
                if page.markedStatus == status, let id = page.sourcedID {
                    shell.library.markedStatus(id, status)
                }
            }
        }
    }
}

extension View {
    /// The label of a round button on a book's screen ("…", ☆): as tall as
    /// the row's other buttons where `fillsHeight`.
    func bookRoundLabel(fillsHeight: Bool) -> some View {
        frame(minWidth: 22, minHeight: 22)
            .frame(maxHeight: fillsHeight ? .infinity : nil)
    }

    /// Its glass: a circle around a glyph, `.capsule` around more.
    func bookRoundButton(_ shape: ButtonBorderShape = .circle) -> some View {
        buttonStyle(.glass)
            .buttonBorderShape(shape)
            .fixedSize(horizontal: true, vertical: false)
    }
}

extension LibraryReadStatus {
    /// More's statuses, in its order. Finished has its own button, and
    /// Rereading shows as Reading (Adam, 2026-11-12).
    static let menu: [LibraryReadStatus] = [.reading, .wantToRead, .onHold, .skimmed, .abandoned, .unread]

    var title: String {
        switch self {
        case .unread: "Unread"
        case .wantToRead: "Want to read"
        case .reading, .rereading: "Reading"
        case .onHold: "On hold"
        case .read: "Finished"
        case .skimmed: "Skimmed"
        case .abandoned: "Abandoned"
        // Never shown: not in the menu, and it has no place word.
        case .other: "Other"
        }
    }

    /// Its glyph in the menu and, for one the place line names, on a cover
    /// in the finished check's place (Adam, 2026-11-13).
    var symbol: String {
        switch self {
        case .unread: "book.closed"
        case .wantToRead: "bookmark"
        case .reading, .rereading: "book"
        case .onHold: "pause"
        case .read: "checkmark"
        case .skimmed: "forward"
        case .abandoned: "xmark"
        case .other: "questionmark"
        }
    }

    /// The place line's word for a status the place alone would misstate:
    /// "On hold · 30%". `nil`: the place says it.
    var placeWord: String? {
        switch self {
        case .wantToRead, .onHold, .skimmed, .abandoned: title
        case .unread, .reading, .rereading, .read, .other: nil
        }
    }

    /// The status More ticks for a book with `status`: Rereading is Reading,
    /// none is Unread, and Finished or one Octavo doesn't know ticks nothing.
    static func ticked(_ status: LibraryReadStatus?) -> LibraryReadStatus? {
        switch status {
        case nil: .unread
        case .rereading: .reading
        case .read, .other: nil
        case let status?: status
        }
    }
}
