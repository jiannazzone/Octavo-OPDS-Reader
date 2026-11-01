import OctavoKit
import SwiftUI

/// The reader (decisions 7–12; frames 07–09 and 14): the page edge to edge,
/// with the text kept out of the system's areas, and the controls hidden
/// until a tap.
///
/// The shell shows it as a layer over the tabs, never as a
/// `fullScreenCover`: a cover presented by an unfold stays laid out for the
/// outer display (`docs/notes/duo-tabbar.md` §6).
struct ReaderView: View {
    let book: OpenedBook
    let close: () -> Void
    // Made in `.task` rather than `init`, so SwiftUI re-creating this view
    // doesn't spin up throwaway web pages.
    @State private var model: ReaderModel?

    var body: some View {
        ZStack {
            if let model {
                ReaderScreen(model: model, close: close)
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }
        }
        .task(id: book.reader) {
            guard model?.book != book.reader else { return }
            #if DEBUG
            model = ReaderModel(book: book.reader, sync: ReaderRemote.sync(for: book), cfiShape: ReaderRemote.cfiShape)
            #else
            model = ReaderModel(book: book.reader)
            #endif
        }
        .onDisappear {
            guard let model else { return }
            Task { await model.close() }
        }
    }
}

/// The page, the column's buttons and the progress bar for one open book.
private struct ReaderScreen: View {
    let model: ReaderModel
    let close: () -> Void
    @AppStorage(ReaderSettings.alwaysShowControlsKey) private var alwaysShowControls = ReaderSettings.alwaysShowControlsDefault
    @AppStorage(ReaderMargins.key) private var margins = ReaderMargins.standard
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var controls = ReaderControls()

    var body: some View {
        NavigationStack {
            ReaderWebView(model: model, showsFooter: !controls.showsBar)
                .overlay { status }
                .overlay(alignment: .topLeading) {
                    if controls.showsBar, model.phase == .open {
                        ReaderProgressBar(model: model)
                            .transition(.opacity)
                    }
                }
                .ignoresSafeArea()
                .accessibilityAction(named: Text(controls.showsBar ? "Hide Controls" : "Show Controls")) {
                    withAnimation { controls.toggle() }
                }
                .toolbar { buttons }
                .toolbar(buttonsVisible ? .visible : .hidden, for: .navigationBar)
        }
        .ignoresSafeArea()
        // Measured outside the stack, so the reader's own toolbar showing or
        // hiding never moves the text, and outside `ignoresSafeArea`, where
        // the view keeps to the safe area and reports how far in it is.
        .onGeometryChange(for: ReaderInsets.self) { [layoutDirection] proxy in
            ReaderInsets(proxy.safeAreaInsets, layoutDirection: layoutDirection)
        } action: { insets in
            model.safeAreaChanged(insets)
        }
        // Without this the measured bottom inset grows by the keyboard's
        // height (34 → 304 pt) and the page re-paginates whenever a panel
        // (#18) brings the keyboard up.
        .ignoresSafeArea(.keyboard)
        .onChange(of: alwaysShowControls, initial: true) { _, always in
            controls.alwaysShowsButtons = always
        }
        .onChange(of: margins, initial: true) { _, margins in
            model.margins = margins
        }
        .onChange(of: controls.coversPage, initial: true) { _, covers in
            model.coversPage = covers
        }
        .task {
            // A binding, not `self`: the model keeps these closures, and
            // capturing the view would keep the model (and its web page)
            // alive after the reader closes.
            let controls = $controls
            model.onControlsTap = { zone in
                withAnimation(.easeOut(duration: 0.2)) {
                    if zone == "dismiss" { controls.wrappedValue.hide() } else { controls.wrappedValue.toggle() }
                }
            }
            model.onBookModeChange = { _ in
                withAnimation(.easeOut(duration: 0.2)) { controls.wrappedValue.hide() }
            }
        }
        #if DEBUG
        .readerRemote(model)
        #endif
    }

    /// A book that couldn't open keeps Back up, so there's a way out.
    private var buttonsVisible: Bool {
        if case .failed = model.phase { return true }
        return controls.buttonsVisible
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .open:
            EmptyView()
        case .failed(let message):
            ContentUnavailableView("Couldn’t Open", systemImage: "exclamationmark.triangle", description: Text(message))
                .background(Color(.systemBackground))
        }
    }

    /// The column's buttons (frame 08). Contents, Text and theme, Search in
    /// book and Bookmark are greyed out until their panels exist (#18).
    @ToolbarContentBuilder private var buttons: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Back", systemImage: "chevron.backward", action: close)
            Button("Contents", systemImage: "list.bullet") {}
                .disabled(true)
            Button("Text and Theme", systemImage: "textformat.size") {}
                .disabled(true)
            Button("Search in Book", systemImage: "magnifyingglass") {}
                .disabled(true)
            Button("Bookmark", systemImage: "bookmark") {}
                .disabled(true)
        }
    }
}

extension ReaderInsets {
    /// SwiftUI's insets in the page's physical directions.
    nonisolated init(_ insets: EdgeInsets, layoutDirection: LayoutDirection) {
        let rightToLeft = layoutDirection == .rightToLeft
        self.init(
            top: Double(insets.top),
            left: Double(rightToLeft ? insets.trailing : insets.leading),
            bottom: Double(insets.bottom),
            right: Double(rightToLeft ? insets.leading : insets.trailing)
        )
    }
}

/// The glass progress bar (decision 7, frames 08 and 09): the chapter, a
/// scrubber through the whole book, and the page numbers. It runs along the
/// bottom of the page, clear of the side column. Half open, it follows the
/// spread: the chapter and scrubber on the left page, the numbers on the
/// right, nothing on the hinge (decision 9).
private struct ReaderProgressBar: View {
    let model: ReaderModel
    /// Where the scrubber is while it's dragged, and after it's let go until
    /// the page gets there.
    @State private var scrub: Double?
    @State private var relocationsAtRelease: Int?

    static let height = 60.0
    static let inset = 12.0

    var body: some View {
        if let geometry = model.geometry {
            let safe = geometry.safeArea
            let width = Double(geometry.size.width)
            let left = safe.left + Self.inset
            let right = width - safe.right - Self.inset
            // Over the home indicator like a tab bar, 12 pt from the edge (frame 08).
            let top = Double(geometry.size.height) - Self.inset - Self.height
            if model.isBookMode, let fold = model.layout.fold, fold.lowerBound - Self.inset > left, fold.upperBound + Self.inset < right {
                glass { scrubber }
                    .frame(width: fold.lowerBound - Self.inset - left, height: Self.height)
                    .offset(x: left, y: top)
                glass { numbers.frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(width: right - fold.upperBound - Self.inset, height: Self.height)
                    .offset(x: fold.upperBound + Self.inset, y: top)
            } else {
                glass {
                    VStack(alignment: .leading, spacing: 2) {
                        scrubber
                        numbers
                    }
                }
                .frame(width: max(0, right - left), height: Self.height)
                .offset(x: left, y: top)
            }
        }
    }

    private var place: ReaderPlace {
        if let scrub {
            return ReaderPlace(fraction: scrub, toc: model.toc, total: model.location?.total)
        }
        return ReaderPlace(chapter: model.chapter, location: model.location, fraction: model.position?.fraction ?? 0)
    }

    private var scrubber: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(place.chapter ?? model.title ?? " ")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Slider(value: fraction, in: 0...1) { editing in
                guard !editing, let scrub else { return }
                relocationsAtRelease = model.relocationCount
                model.goTo(fraction: scrub)
            }
            .controlSize(.mini)
            .accessibilityLabel("Position in Book")
            .accessibilityValue(place.barLine(spread: false))
        }
        .onChange(of: model.relocationCount) { _, count in
            if let relocationsAtRelease, count > relocationsAtRelease {
                scrub = nil
                self.relocationsAtRelease = nil
            }
        }
    }

    private var numbers: some View {
        Text(place.barLine(spread: model.layout.columns == 2))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var fraction: Binding<Double> {
        Binding {
            scrub ?? model.position?.fraction ?? 0
        } set: {
            relocationsAtRelease = nil
            scrub = $0
        }
    }

    private func glass(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.horizontal, 16)
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// The chapter and page in each page's bottom margin, outside the text
/// (decision 7): one line per page, the chapter on the first and the numbers
/// on the last, so a spread splits at the gutter. Under the fold's
/// cross-fade; ignores touches.
struct ReaderFooter: View {
    let model: ReaderModel

    var body: some View {
        if model.phase == .open, let geometry = model.geometry,
           let columns = model.layout.textColumns(inReaderWidth: Double(geometry.size.width)),
           let first = columns.first, let last = columns.last {
            let place = ReaderPlace(chapter: model.chapter, location: model.location, fraction: model.position?.fraction ?? 0)
            let spread = columns.count > 1
            let centre = Double(geometry.size.height) - model.layout.bottomInset - ReaderLayout.verticalMargin / 2
            Group {
                if spread {
                    line(chapter: place.chapter, numbers: nil, in: first, centre: centre)
                    line(chapter: nil, numbers: place.footer(spread: true), in: last, centre: centre)
                } else {
                    line(chapter: place.chapter, numbers: place.footer(spread: false), in: first, centre: centre)
                }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func line(chapter: String?, numbers: String?, in column: ClosedRange<Double>, centre: Double) -> some View {
        HStack(spacing: 12) {
            if let chapter {
                Text(chapter)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let numbers {
                Text(numbers)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .frame(width: column.upperBound - column.lowerBound, height: 20)
        .offset(x: column.lowerBound, y: centre - 10)
    }
}
