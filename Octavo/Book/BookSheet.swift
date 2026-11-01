import OctavoKit
import SwiftUI

/// The cover's glass sheet (decision 20): at its compact height the strip
/// (place, Open, progress); swiped up, the same sheet keeps the strip and
/// adds the details below it. Drag the strip, or tap the grabber, to switch.
///
/// Drawn by the cover page rather than presented, so unfolded it stays
/// inside the right-hand pane and a fold never catches it mid-presentation
/// (`docs/notes/duo-tabbar.md` §6).
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
            BookStrip(page: page, source: source)
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

/// The strip at the top of the sheet: the place and Open, or a download's
/// progress or problem in Open's place (decision 22).
struct BookStrip: View {
    let page: BookPage
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell

    var body: some View {
        if let message {
            CoverStripStatus(message: message, action: act)
        } else {
            let progress = page.progress()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    // #11 adds the chapter here and a "Synced …" line below.
                    Text(BookPage.placeLine(progress: progress))
                        .font(.headline)
                    Spacer(minLength: 8)
                    Button("Open") { shell.opener.open(page.current, from: source) }
                        .buttonStyle(.glassProminent)
                        .disabled(!shell.opener.canOpen(page.current))
                }
                ProgressView(value: progress ?? 0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var message: CoverStripMessage? {
        if let standIn = shell.coverStrip { return standIn }
        return switch shell.opener.status(of: page.current) {
        case .downloading(let fraction, opensWhenDone: true): .downloading(fraction: fraction)
        case .failed(offline: true, _): .needsConnection
        case .failed(offline: false, _): .downloadFailed
        default: nil
        }
    }

    private func act() {
        if shell.coverStrip != nil {
            shell.coverStrip = nil
            return
        }
        switch shell.opener.status(of: page.current) {
        case .downloading: shell.opener.cancel(page.current)
        case .failed: shell.opener.retry(page.current, from: source)
        default: break
        }
    }
}

/// Below the strip (decision 20): title and author, Mark as finished and
/// Download, the description, then Series, Collections, File, From, Added.
struct BookDetails: View {
    let page: BookPage
    let source: any LibrarySource
    @Environment(\.openLibraryEntry) private var openLibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.current.title.isEmpty ? "Untitled" : page.current.title)
                    .font(.title3.weight(.semibold))
                author
            }
            HStack(spacing: 10) {
                // Sending it to BookOrbit is #11 (decision 20); until then
                // the button shows but does nothing.
                Button("Mark as finished", systemImage: "checkmark") {}
                    .buttonStyle(.glass)
                    .disabled(true)
                BookDownloadButton(page: page, source: source)
            }
            if let description = page.plainDescription {
                BookDescription(text: description, isExpanded: Bindable(page).showsFullDescription)
            } else if page.details == nil, !page.detailsFailed {
                ProgressView()
                    .frame(maxWidth: .infinity)
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
        }
    }

    /// Tapping the author opens their books (decision 20), once the Library
    /// provides a way to open them (#13).
    @ViewBuilder
    private var author: some View {
        let line = page.authorLine
        if let entry = page.details?.authors.first, let openLibraryEntry {
            Button {
                openLibraryEntry(entry)
            } label: {
                HStack(spacing: 4) {
                    Text(line)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        } else if !line.isEmpty {
            Text(line)
                .foregroundStyle(.secondary)
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

/// Download, its progress as a ring (tap to cancel), then a check once the
/// book is on the iPhone. Remove download is #10.
struct BookDownloadButton: View {
    let page: BookPage
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let opener = shell.opener
        let book = page.current
        switch opener.status(of: book) {
        case .downloading(let fraction, _):
            Button {
                opener.cancel(book)
            } label: {
                DownloadRing(fraction: fraction)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Cancel download")
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        case .downloaded:
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
                .padding(10)
                .glassEffect(in: .circle)
                .accessibilityLabel("Downloaded")
        case .notDownloaded, .failed:
            Button {
                opener.download(book, from: source)
            } label: {
                Image(systemName: "arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!opener.canOpen(book))
            .accessibilityLabel("Download")
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
}
