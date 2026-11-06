import OctavoKit
import SwiftUI

/// The cover's glass sheet, folded: at rest a compact summary (the title
/// over the place, Open beside them, a progress line under them); pulled
/// up, the same sheet keeps the summary and adds the author, Mark finished
/// and the details below it. Drag the summary, or tap the grabber, to
/// switch.
///
/// Drawn by the cover page rather than presented, so a fold never catches
/// it mid-presentation (`docs/notes/duo-tabbar.md` §6); unfolded, the right
/// page shows the full summary and details instead.
struct BookSheet: View {
    let page: BookPage
    let source: any LibrarySource
    let sourceID: LibrarySourceID
    @Environment(ShellModel.self) private var shell
    @GestureState private var drag: CGFloat = 0

    /// With Reduce Motion, no bounce.
    static var animation: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeOut(duration: 0.2) : .snappy(duration: 0.35)
    }
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
                    details
                    ScrollView { details }
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
            BookSheetSummary(page: page, source: source, sourceID: sourceID)
                // Pulled up at the largest text sizes, the details scroll instead.
                .fixedSize(horizontal: false, vertical: true)
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

    /// Pulled up: the author and Mark finished, which the resting summary
    /// leaves out, then the details.
    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            BookAuthorLink(page: page)
            BookFinishedButton(page: page, source: source)
            BookDetails(page: page, source: source, sourceID: sourceID)
        }
        .padding(16)
    }
}

/// The sheet's top, folded (Adam, 2026-11-03): the title on one line over
/// the place, Open on the right of both, and a thin progress line under
/// them. Until the book is on the iPhone, Open is Download; a download's
/// progress and problems show in its place (decision 22).
struct BookSheetSummary: View {
    let page: BookPage
    let source: any LibrarySource
    let sourceID: LibrarySourceID
    @Environment(ShellModel.self) private var shell
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let place = BookPlace(page: page, sourceID: sourceID, shell: shell)
        VStack(alignment: .leading, spacing: 12) {
            LargerTextStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.current.title.isEmpty ? "Untitled" : page.current.title)
                        .font(.headline)
                        // In full once pulled up, as the details' heading.
                        .lineLimit(untilLargerText: page.isExpanded ? 2 : 1)
                        .accessibilityAddTraits(.isHeader)
                    // Redrawn each minute, so "just now" moves on.
                    TimelineView(.everyMinute) { context in
                        Text(place.line(now: context.date))
                            .font(.subheadline)
                            .foregroundStyle(.secondaryOnGlass)
                            // A problem says what to do, so it may wrap.
                            .lineLimit(untilLargerText: place.problem == nil ? 1 : 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BookOpenButton(page: page, source: source, sourceID: sourceID, fillsWidth: size.isAccessibilitySize)
                    .fixedSize(horizontal: !size.isAccessibilitySize, vertical: !size.isAccessibilitySize)
            }
            BookPlaceLine(place: place)
        }
    }
}

/// The top of a book's right page unfolded: the title and author, the
/// place (with when it last synced) over the progress bar, then Mark
/// finished and Open. Until the book is on the iPhone, Open is Download; a
/// download's progress and problems show in its place (decision 22).
struct BookSummary: View {
    let page: BookPage
    let source: any LibrarySource
    let sourceID: LibrarySourceID
    var titleFont: Font = .title3.weight(.semibold)
    var titleLines = 2
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.current.title.isEmpty ? "Untitled" : page.current.title)
                    .font(titleFont)
                    .lineLimit(untilLargerText: titleLines)
                    .accessibilityAddTraits(.isHeader)
                BookAuthorLink(page: page)
            }
            place
            LargerTextStack(spacing: 10) {
                BookFinishedButton(page: page, source: source)
                BookOpenButton(page: page, source: source, sourceID: sourceID)
            }
        }
    }

    /// "30%", "Finished", or a problem, over the progress bar. Beside the
    /// place, when it last synced (step 13, Adam: on the same line, and
    /// nothing for a book that doesn't sync).
    private var place: some View {
        let place = BookPlace(page: page, sourceID: sourceID, shell: shell)
        return VStack(alignment: .leading, spacing: 6) {
            LargerTextStack(alignment: .firstTextBaseline, spacing: 12, stackedSpacing: 2) {
                Text(place.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trip = place.trip {
                    Text(trip.opensAtLabel)
                        .lineLimit(untilLargerText: 1)
                } else if let status = place.status {
                    // Redrawn each minute, so "just now" moves on.
                    TimelineView(.everyMinute) { context in
                        Text(status.text(now: context.date))
                            .lineLimit(untilLargerText: 1)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondaryOnGlass)
            BookPlaceLine(place: place)
        }
    }
}

/// The book's screen's thin line. On a trip the fill runs from your place to
/// where the book opens, as the scrubber's does (decision 33).
private struct BookPlaceLine: View {
    let place: BookPlace

    var body: some View {
        Group {
            if let trip = place.trip {
                GeometryReader { proxy in
                    let low = min(trip.placeFraction, trip.pageFraction)
                    let high = max(trip.placeFraction, trip.pageFraction)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(.tint)
                            .frame(width: max((high - low) * proxy.size.width, 4))
                            .offset(x: low * proxy.size.width)
                    }
                }
                .frame(height: 4)
            } else {
                ProgressView(value: place.progress ?? 0)
            }
        }
        .accessibilityHidden(true)
    }
}

/// What a book's place line says: "30%", "Finished", or a problem, and
/// when the place last synced, for a book that syncs (step 13).
struct BookPlace {
    /// How far through, for the progress bar.
    let progress: Double?
    /// A download or Mark finished that went wrong, in the place's stead.
    let problem: String?
    let status: BookPlaces.Status?
    /// Away from your place, the book reopens where you were looking (decision 33).
    let trip: ReaderTrip?
    private let finished: Bool

    init(page: BookPage, sourceID: LibrarySourceID, shell: ShellModel) {
        let book = SourcedBook(source: sourceID, book: page.current)
        self.init(
            progress: shell.places.progress(of: book),
            problem: Self.problem(BookOpenButton.state(of: book, in: shell), finishedFailed: page.finishedFailed),
            status: shell.places.status(of: book),
            trip: shell.places.trip(of: book),
            finished: page.isFinished
        )
    }

    /// A finished book's bar is full; finished or a problem leaves out the
    /// sync.
    init(progress: Double?, problem: String?, status: BookPlaces.Status?, trip: ReaderTrip? = nil, finished: Bool) {
        self.progress = finished ? 1 : progress
        self.problem = problem
        self.status = problem == nil && !finished ? status : nil
        self.trip = problem == nil && !finished ? trip : nil
        self.finished = finished
    }

    static func problem(_ state: BookOpenButton.State, finishedFailed: Bool) -> String? {
        switch state {
        case .failed(offline: true): return "Needs a connection to download."
        case .failed(offline: false): return "Couldn’t download. Check your connection."
        case .protected: return "This file is DRM-protected and cannot be opened."
        default: break
        }
        if finishedFailed { return "Couldn’t mark it finished. Check your connection." }
        return nil
    }

    /// The place alone: "30%", "Not started", "Finished", or the problem.
    var text: String {
        problem ?? (finished ? "Finished" : BookPage.placeLine(progress: progress))
    }

    /// The place and when it last synced on one line, as the folded sheet
    /// shows it: "48% · Synced just now".
    func line(now: Date) -> String {
        if let trip { return "\(text) · \(trip.opensAtLabel)" }
        guard let status else { return text }
        return "\(text) · \(status.text(now: now))"
    }
}

/// The author; tapping them opens their books, where the screen provides a
/// way to open them.
struct BookAuthorLink: View {
    let page: BookPage
    @Environment(\.openLibraryEntry) private var openLibraryEntry

    var body: some View {
        let line = page.authorLine
        if let entry = page.details?.authors.first, let openLibraryEntry {
            Button {
                openLibraryEntry(entry)
            } label: {
                HStack(spacing: 4) {
                    Text(line)
                        .lineLimit(untilLargerText: 1)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        } else if !line.isEmpty {
            Text(line)
                .lineLimit(untilLargerText: 1)
                .foregroundStyle(.secondaryOnGlass)
        }
    }
}

/// Mark finished, or Finished once it is; tapping again takes the mark off.
struct BookFinishedButton: View {
    let page: BookPage
    let source: any LibrarySource
    @Environment(ShellModel.self) private var shell

    var body: some View {
        let finished = page.isFinished
        Button {
            Task {
                await page.setFinished(!finished, from: source)
                // Home lists only books in progress.
                if page.isFinished != finished, let id = page.sourcedID {
                    shell.library.markedFinished(id, !finished)
                }
            }
        } label: {
            Label(finished ? "Finished" : "Mark finished", systemImage: finished ? "checkmark.circle.fill" : "checkmark")
                .lineLimit(untilLargerText: 1)
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
    let sourceID: LibrarySourceID
    /// As wide as the space it's given (unfolded, beside Mark finished), or
    /// as wide as its label (the folded sheet's capsule).
    var fillsWidth = true
    @Environment(ShellModel.self) private var shell
    @Environment(\.openBook) private var openBook
    @Environment(\.downloadBook) private var downloadBook

    enum State: Equatable {
        case open, download
        case downloading(fraction: Double)
        case failed(offline: Bool)
        /// Downloaded, and refused for its DRM.
        case protected
    }

    /// The opener's state, or the debug stand-in (`-shellCoverStrip`).
    static func state(of book: SourcedBook, in shell: ShellModel) -> State {
        switch shell.coverStrip {
        case .downloadFailed: return .failed(offline: false)
        case .needsConnection: return .failed(offline: true)
        case .downloading(let fraction): return .downloading(fraction: fraction)
        case .protected: return .protected
        case nil: break
        }
        return switch shell.opener.status(of: book) {
        case .downloaded: .open
        case .notDownloaded: .download
        case .downloading(let fraction, _): .downloading(fraction: fraction)
        case .failed(let offline, _): .failed(offline: offline)
        case .protected: .protected
        }
    }

    var body: some View {
        let book = page.current
        let sourced = SourcedBook(source: sourceID, book: book)
        let opener = shell.opener
        switch Self.state(of: sourced, in: shell) {
        case .open:
            Button {
                if let openBook { openBook(book) } else { opener.open(sourced, from: source) }
            } label: {
                Text("Open")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(.onAccent)
            .disabled(!opener.canOpen(book))
        case .download:
            Button {
                if let downloadBook { downloadBook(book) } else { opener.download(sourced, from: source) }
            } label: {
                Label("Download", systemImage: "arrow.down")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(.onAccent)
            .disabled(!opener.canOpen(book))
        case .downloading(let fraction):
            Button {
                if shell.coverStrip != nil { shell.coverStrip = nil } else { opener.cancel(sourced) }
            } label: {
                HStack(spacing: 8) {
                    DownloadRing(fraction: fraction)
                    Text("Cancel")
                }
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Cancel download")
            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
        case .failed:
            Button {
                if shell.coverStrip != nil { shell.coverStrip = nil } else { opener.retry(sourced, from: source) }
            } label: {
                Text("Try again")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(.onAccent)
        case .protected:
            // Greyed out, as for a format the reader can't open.
            Button {} label: {
                Label("Download", systemImage: "arrow.down")
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(.onAccent)
            .disabled(true)
        }
    }
}

/// Below the summary: the description, then Series, Collections, File,
/// From and Added, then Remove download once the book is on the iPhone.
struct BookDetails: View {
    let page: BookPage
    let source: any LibrarySource
    let sourceID: LibrarySourceID
    @Environment(ShellModel.self) private var shell
    @State private var confirmsRemoval = false
    @State private var removingImported: SourcedBook?

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
                        .foregroundStyle(.secondaryOnGlass)
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
                row("From", serverName)
                Divider()
                row("Added", page.addedLine)
            }
            if sourceID == .files {
                // The only copy: Remove from iPhone, always asked (Adam,
                // 2026-11-02).
                Button("Remove from iPhone", role: .destructive) {
                    removingImported = SourcedBook(source: sourceID, book: page.current)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .confirmRemovingImported($removingImported)
            } else if shell.opener.status(of: SourcedBook(source: sourceID, book: page.current)) == .downloaded {
                removeDownload
            }
        }
    }

    /// The name the book's server goes by, else what its library calls
    /// itself.
    private var serverName: String? {
        shell.library.server(sourceID)?.name ?? page.serverName
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
                    withAnimation { shell.opener.removeDownload(SourcedBook(source: sourceID, book: page.current)) }
                }
            } message: {
                Text("Your place is kept. You can download it again from \(serverName ?? "the server").")
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
    /// Downloads the book without opening it (Download). The shell provides
    /// it so Search can find the book on the iPhone; without it the opener
    /// downloads directly.
    @Entry var downloadBook: ((LibraryBook) -> Void)?
}
