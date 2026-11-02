import OctavoKit
import SwiftUI

/// The cover's glass sheet, folded: at rest the book's summary (title,
/// place, Download, Open); pulled up, the same sheet keeps the summary and
/// adds the details below it. Drag the summary, or tap the grabber, to
/// switch.
///
/// Drawn by the cover page rather than presented, so a fold never catches
/// it mid-presentation (`docs/notes/duo-tabbar.md` §6); unfolded, the right
/// page shows the same summary and details instead.
struct BookSheet: View {
    let page: BookPage
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell
    @GestureState private var drag: CGFloat = 0

    static let animation = Animation.snappy(duration: 0.35)
    /// How much more than the status bar's height of cover shows above the
    /// expanded sheet, to tap back to the strip (frame 15).
    static let expandedTopInset: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            header
            if page.isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                // Only as tall as the details, up to the top of the screen.
                ViewThatFits(in: .vertical) {
                    BookDetails(page: page, source: source)
                        .padding(16)
                    ScrollView {
                        BookDetails(page: page, source: source)
                            .padding(16)
                    }
                }
                .transition(.opacity)
            }
        }
        .glassEffect(in: .rect(cornerRadius: 28))
        .padding(.top, page.isExpanded ? Self.expandedTopInset : 0)
        .offset(y: rubberBand(drag))
    }

    private var header: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(Self.animation) { page.isExpanded.toggle() }
            } label: {
                Capsule()
                    .fill(.secondary)
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(page.isExpanded ? "Hide details" : "Show details")
            BookSummary(page: page, source: source)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in
                    let distance = value.predictedEndTranslation.height
                    if distance < -60, !page.isExpanded {
                        withAnimation(Self.animation) { page.isExpanded = true }
                    } else if distance > 60, page.isExpanded {
                        withAnimation(Self.animation) { page.isExpanded = false }
                    }
                }
        )
    }

    /// Follows the finger a little, so the drag feels attached before it
    /// switches heights.
    private func rubberBand(_ translation: CGFloat) -> CGFloat {
        let toward = page.isExpanded ? max(translation, 0) : min(translation, 0)
        return toward / 4
    }
}

/// The top of a book's sheet, and of its right page unfolded: the title
/// and author, the place over the progress bar, then Mark finished and
/// Open. Until the book is on the iPhone, Open is Download; a download's
/// progress and problems show in its place (decision 22).
struct BookSummary: View {
    let page: BookPage
    let source: any LibrarySource
    var titleFont: Font = .title3.weight(.semibold)
    var titleLines = 2
    @Environment(ShellModel.self) private var shell
    @Environment(\.openLibraryEntry) private var openLibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.current.title.isEmpty ? "Untitled" : page.current.title)
                    .font(titleFont)
                    .lineLimit(titleLines)
                    .accessibilityAddTraits(.isHeader)
                author
            }
            place
            HStack(spacing: 10) {
                BookFinishedButton(page: page, source: source)
                BookOpenButton(page: page, source: source)
            }
        }
    }

    /// "30%", "Finished", or a problem, over the progress bar.
    private var place: some View {
        let progress = page.isFinished ? 1 : page.progress()
        return VStack(alignment: .leading, spacing: 6) {
            // #11 adds the chapter here and a "Synced …" line.
            Text(placeLine(progress: progress))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressView(value: progress ?? 0)
                .accessibilityHidden(true)
        }
    }

    private func placeLine(progress: Double?) -> String {
        switch BookOpenButton.state(of: page.current, in: shell) {
        case .failed(offline: true): return "Needs a connection to download."
        case .failed(offline: false): return "Couldn’t download. Check your connection."
        default: break
        }
        if page.finishedFailed { return "Couldn’t mark it finished. Check your connection." }
        if page.isFinished { return "Finished" }
        return BookPage.placeLine(progress: progress)
    }

    /// Tapping the author opens their books, where the screen provides a
    /// way to open them.
    @ViewBuilder
    private var author: some View {
        let line = page.authorLine
        if let entry = page.details?.authors.first, let openLibraryEntry {
            Button {
                openLibraryEntry(entry)
            } label: {
                HStack(spacing: 4) {
                    Text(line)
                        .lineLimit(1)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        } else if !line.isEmpty {
            Text(line)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }
}

/// Mark finished, or Finished once it is; tapping again takes the mark off.
struct BookFinishedButton: View {
    let page: BookPage
    let source: any LibrarySource

    var body: some View {
        let finished = page.isFinished
        Button {
            Task { await page.setFinished(!finished, from: source) }
        } label: {
            Label(finished ? "Finished" : "Mark finished", systemImage: finished ? "checkmark.circle.fill" : "checkmark")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Finished")
        .accessibilityValue(finished ? "On" : "Off")
    }
}

/// Open once the book is on the iPhone; before that Download, then its
/// progress (tap to cancel), or Try again after a problem.
struct BookOpenButton: View {
    let page: BookPage
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell
    @Environment(\.openBook) private var openBook

    enum State: Equatable {
        case open, download
        case downloading(fraction: Double)
        case failed(offline: Bool)
    }

    /// The opener's state, or the debug stand-in (`-shellCoverStrip`).
    static func state(of book: LibraryBook, in shell: ShellModel) -> State {
        switch shell.coverStrip {
        case .downloadFailed: return .failed(offline: false)
        case .needsConnection: return .failed(offline: true)
        case .downloading(let fraction): return .downloading(fraction: fraction)
        case nil: break
        }
        return switch shell.opener.status(of: book) {
        case .downloaded: .open
        case .notDownloaded: .download
        case .downloading(let fraction, _): .downloading(fraction: fraction)
        case .failed(let offline, _): .failed(offline: offline)
        }
    }

    var body: some View {
        let book = page.current
        let opener = shell.opener
        switch Self.state(of: book, in: shell) {
        case .open:
            Button {
                if let openBook { openBook(book) } else { opener.open(book, from: source) }
            } label: {
                Text("Open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!opener.canOpen(book))
        case .download:
            Button {
                opener.download(book, from: source)
            } label: {
                Label("Download", systemImage: "arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(!opener.canOpen(book))
        case .downloading(let fraction):
            Button {
                if shell.coverStrip != nil { shell.coverStrip = nil } else { opener.cancel(book) }
            } label: {
                HStack(spacing: 8) {
                    DownloadRing(fraction: fraction)
                    Text("Cancel")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Cancel download")
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        case .failed:
            Button {
                if shell.coverStrip != nil { shell.coverStrip = nil } else { opener.retry(book, from: source) }
            } label: {
                Text("Try again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
    }
}

/// Below the summary: the description, then Series, Collections, File,
/// From and Added, then Remove download once the book is on the iPhone.
struct BookDetails: View {
    let page: BookPage
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell
    @State private var confirmsRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let description = page.plainDescription {
                BookDescription(text: description, isExpanded: Bindable(page).showsFullDescription)
            } else if page.details == nil, !page.detailsFailed {
                // Placeholder lines, not a spinner, while the details load.
                Text(verbatim: String(repeating: "Placeholder description text ", count: 6))
                    .lineLimit(3)
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
            if page.detailsFailed {
                HStack {
                    Text("Couldn’t load the details.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Try again") { Task { await page.retryDetails(from: source) } }
                }
                .font(.subheadline)
            }
            VStack(spacing: 0) {
                row("Series", page.seriesLine)
                Divider()
                row("Collections", page.collectionsLine)
                Divider()
                row("File", page.fileLine)
                Divider()
                row("From", page.serverName)
                Divider()
                row("Added", page.addedLine)
            }
            if shell.opener.status(of: page.current) == .downloaded {
                removeDownload
            }
        }
    }

    /// Asks first: the one pop-up the app allows is a confirmation to
    /// remove something (decision 22).
    private var removeDownload: some View {
        Button("Remove download", role: .destructive) { confirmsRemoval = true }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .confirmationDialog(
                "Remove “\(page.current.title.isEmpty ? "Untitled" : page.current.title)” from this iPhone?",
                isPresented: $confirmsRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove download", role: .destructive) {
                    withAnimation { shell.opener.removeDownload(page.current) }
                }
            } message: {
                Text("Your place is kept. You can download it again from \(page.serverName ?? "the server").")
            }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        LabeledContent(label) {
            Text(value ?? "—")
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// The description, three lines until More (decision 20). Plain text
/// only: the book controls its markup.
struct BookDescription: View {
    let text: String
    @Binding var isExpanded: Bool
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: text)
                .lineLimit(isExpanded ? nil : 3)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                .background(alignment: .top) {
                    Text(verbatim: text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if !isExpanded, fullHeight > shownHeight + 1 {
                Button("More") { withAnimation(BookSheet.animation) { isExpanded = true } }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
    }
}

/// A download's progress around a stop square, as the App Store draws it.
struct DownloadRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(fraction, 0.02))
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: fraction)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.tint)
                .frame(width: 7, height: 7)
        }
        .frame(width: 24, height: 24)
    }
}

extension EnvironmentValues {
    /// Opens a library entry's books, such as an author's (decision 20).
    /// The Library (#13) provides it; without it the author isn't a link.
    @Entry var openLibraryEntry: ((LibraryEntry) -> Void)?
    /// Opens the book in the reader (Open). The shell (#13) provides it so
    /// the book joins Home's Continue reading; without it the opener opens
    /// the book directly.
    @Entry var openBook: ((LibraryBook) -> Void)?
}
