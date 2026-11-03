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
    /// Where the book's bookmarks sync, if anywhere.
    var bookmarkSync: (any BookmarkSync)?
    /// Where the book's place syncs, if anywhere, and the server's place
    /// from the library list for when it can't pull (`ReaderModel.fallback`).
    var progressSync: (any ProgressSync)?
    var listedPlace: SyncedPosition?
    /// Counts the times the connection came back (`ConnectionMonitor`).
    var connectionReturns = 0
    let close: () -> Void
    // Made in `.task` rather than `init`, so SwiftUI re-creating this view
    // doesn't spin up throwaway web pages.
    @State private var model: ReaderModel?

    var body: some View {
        ZStack {
            if let model {
                ReaderScreen(model: model, connectionReturns: connectionReturns, close: close)
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }
        }
        .task(id: book.reader) {
            guard model?.book != book.reader else { return }
            let bookmarks = ReaderBookmarks(bookID: book.reader.id, sync: bookmarkSync)
            #if DEBUG
            let cfiShape = ReaderRemote.cfiShape
            #else
            let cfiShape = ReaderMessage.CFIShape.point
            #endif
            model = ReaderModel(book: book.reader, sync: progressSync, fallback: listedPlace, bookmarks: bookmarks, cfiShape: cfiShape)
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
    let connectionReturns: Int
    let close: () -> Void
    @AppStorage(ReaderSettings.alwaysShowControlsKey) private var alwaysShowControls = ReaderSettings.alwaysShowControlsDefault
    @AppStorage(ReaderMargins.key) private var margins = ReaderMargins.standard
    @AppStorage(ReaderAppearance.key) private var appearance = ReaderAppearance()
    @AppStorage(ReaderPageTurn.key) private var pageTurn = ReaderPageTurn.standard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    /// The iPhone's own, read outside the reader's: the reader takes its
    /// theme's.
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var controls = ReaderControls()
    @State private var panel: ReaderPanel?
    /// Where the open panel's button is, for the panel to grow out of.
    @State private var panelButtonFrame: CGRect?
    /// How far the keyboard comes up over the reader, for Search's panel.
    @State private var keyboard: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            // The bars take the footer's place: the progress bar, the step
            // bar while stepping through search matches, or the server's place.
            ReaderWebView(model: model, showsFooter: !controls.showsBar && footerBar == nil)
                .overlay { status }
                .overlay(alignment: .topLeading) {
                    if controls.showsBar, model.phase == .open {
                        ReaderProgressBar(model: model)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if model.bookmarks.pageIsBookmarked, model.phase == .open, let geometry = model.geometry {
                        ReaderRibbon()
                            .offset(x: geometry.size.width - geometry.safeArea.right - 30)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.bookmarks.pageIsBookmarked)
                .overlay(alignment: .bottomLeading) {
                    if let footerBar, let geometry = model.geometry {
                        // Under the page, or the right page of a spread:
                        // nothing spans the hinge (decision 9).
                        let right = Double(geometry.size.width) - geometry.safeArea.right
                        let left = model.layout.columns == 2 ? (model.layout.fold?.upperBound ?? geometry.safeArea.left) : geometry.safeArea.left
                        Group {
                            switch footerBar {
                            case .search:
                                searchBar
                            case .serverPlace(let place):
                                ReaderServerPlaceBar(place: place, go: model.goToServerPlace, stay: model.keepThisPlace)
                            }
                        }
                        .frame(width: max(0, right - left))
                        .padding(.leading, left)
                        .padding(.bottom, max(geometry.safeArea.bottom, 12) + 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: footerBar)
                .overlay(alignment: .topLeading) {
                    if let panel, model.phase == .open, let geometry = model.geometry {
                        let fold = model.layout.columns == 2 ? model.layout.fold : nil
                        ReaderPanelFrame(geometry: geometry, fold: fold, source: panelButtonFrame, fillsSheet: panel != .textAndTheme, keyboard: keyboard) {
                            switch panel {
                            case .textAndTheme:
                                ReaderTextPanel(appearance: $appearance, darkMode: darkMode, showsAll: fold != nil)
                            case .contents:
                                contentsPanel
                            case .search:
                                searchPanel
                            }
                        }
                        // Another panel grows out of its own button.
                        .id(panel)
                    }
                }
                .ignoresSafeArea()
                .accessibilityAction(named: Text(controls.showsBar ? "Hide Controls" : "Show Controls")) {
                    withAnimation { controls.toggle() }
                }
                .toolbar { buttons }
                .toolbar(buttonsVisible || showsControlsButton ? .visible : .hidden, for: .navigationBar)
        }
        // The column's buttons, the footer, the bar and the panel in the
        // page's colours. Here, not for the window, so `systemColorScheme`
        // stays the iPhone's.
        .environment(\.colorScheme, appearance.theme(darkMode: darkMode).isDark ? .dark : .light)
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
        .onChange(of: pageTurn, initial: true) { _, pageTurn in
            model.pageTurn = pageTurn
        }
        .onChange(of: reduceMotion, initial: true) { _, reduceMotion in
            model.reduceMotion = reduceMotion
        }
        .onChange(of: controls.coversPage || panel != nil, initial: true) { _, covers in
            model.coversPage = covers
        }
        .onChange(of: panel) { _, panel in
            if panel == .contents { Task { await model.placeOnScreen() } }
        }
        // Another reader may have moved on while the app was away, or a
        // place may not have gone for want of a connection.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.catchUp() } }
        }
        .onChange(of: connectionReturns) {
            Task { await model.catchUp() }
        }
        .task {
            // The keyboard's top, as far up the reader as it comes. The
            // reader ignores the keyboard's safe area (see above), so the
            // panels move by this instead.
            for await note in NotificationCenter.default.notifications(named: UIResponder.keyboardWillChangeFrameNotification) {
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let screen = (UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)?.screen
                else { continue }
                let overlap = max(0, screen.bounds.maxY - frame.minY)
                withAnimation(.easeOut(duration: 0.25)) { keyboard = Double(overlap) }
            }
        }
        .onChange(of: appearance, initial: true) { _, appearance in
            model.appearance = appearance.script(darkMode: darkMode)
        }
        .onChange(of: darkMode) { _, darkMode in
            model.appearance = appearance.script(darkMode: darkMode)
        }

        .task {
            // A binding, not `self`: the model keeps these closures, and
            // capturing the view would keep the model (and its web page)
            // alive after the reader closes.
            let controls = $controls
            let panel = $panel
            model.onControlsTap = { zone in
                withAnimation(.easeOut(duration: 0.2)) {
                    if zone == "dismiss" {
                        // Back to reading in one tap, panel and all.
                        panel.wrappedValue = nil
                        controls.wrappedValue.hide()
                    } else {
                        controls.wrappedValue.toggle()
                    }
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

    private var darkMode: Bool { systemColorScheme == .dark }

    /// A book that couldn't open keeps Back up, so there's a way out.
    private var buttonsVisible: Bool {
        if case .failed = model.phase { return true }
        return controls.buttonsVisible
    }

    /// Bar hidden: a quiet "…" in the column is the one way to bring the
    /// controls up, in every posture (Adam, 2026-11-02; a middle tap would
    /// land on the fold half open). The rest of the column turns the page.
    /// With Always show controls it sits after the buttons and brings up
    /// the bar. Not while a panel is open: the bar would run under it.
    private var showsControlsButton: Bool {
        model.phase == .open && !controls.showsBar && panel == nil
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

    /// The column's buttons (frame 08).
    @ToolbarContentBuilder private var buttons: some ToolbarContent {
        if showsControlsButton, !buttonsVisible {
            ToolbarItem(placement: .topBarTrailing) { showControlsButton }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if buttonsVisible {
                Button("Back", systemImage: "chevron.backward", action: close)
                panelButton(.contents, title: "Contents", systemImage: "list.bullet")
                panelButton(.textAndTheme, title: "Text and Theme", systemImage: "textformat.size")
                panelButton(.search, title: "Search in Book", systemImage: "magnifyingglass")
                let bookmarked = model.bookmarks.pageIsBookmarked
                Button(bookmarked ? "Remove Bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.fill" : "bookmark") {
                    model.toggleBookmark()
                }
                .tint(bookmarked ? ReaderRibbon.color : nil)
                if showsControlsButton {
                    showControlsButton
                }
            }
        }
    }

    /// A column button that opens `selected`, lit while it's open. Another
    /// panel's button switches to its own.
    private func panelButton(_ selected: ReaderPanel, title: LocalizedStringResource, systemImage: String) -> some View {
        Button(String(localized: title), systemImage: systemImage) {
            if panel != selected {
                panelButtonFrame = Self.columnButtonFrame(titled: String(localized: title))
            }
            withAnimation(ReaderPanel.animation) {
                if panel == selected {
                    panel = nil
                    controls.panelClosed()
                } else {
                    if panel == nil { controls.panelOpened() }
                    panel = selected
                }
            }
        }
        .tint(panel == selected ? .accentColor : nil)
        .accessibilityAddTraits(panel == selected ? .isSelected : [])
    }

    private var contentsPanel: some View {
        ReaderContentsPanel(
            rows: model.contentsRows,
            current: model.currentContentsRow,
            bookmarks: model.bookmarks.list,
            page: { [total = model.location?.total] in ReaderModel.page(at: $0, total: total) },
            goToRow: { row in
                model.goTo(row)
                backToReading()
            },
            goToBookmark: { bookmark in
                model.goTo(bookmark)
                backToReading()
            },
            remove: { model.bookmarks.remove($0) }
        )
    }

    private var searchPanel: some View {
        ReaderSearchPanel(
            search: model.search,
            page: { [total = model.location?.total] in ReaderModel.page(at: $0, total: total) },
            run: { model.runSearch(submitted: $0) },
            choose: { index in
                model.showMatch(index)
                backToReading()
            }
        )
    }

    /// What takes the footer's place while no panel or progress bar is up.
    private enum FooterBar: Equatable {
        case search
        case serverPlace(ReaderServerPlace)
    }

    private var footerBar: FooterBar? {
        guard panel == nil, !controls.showsBar, model.phase == .open else { return nil }
        if model.search.isStepping { return .search }
        return model.serverPlace.map(FooterBar.serverPlace)
    }

    private var searchBar: some View {
        ReaderSearchBar(
            search: model.search,
            step: { model.showMatch($0) },
            showList: {
                withAnimation(ReaderPanel.animation) {
                    panelButtonFrame = nil
                    controls.panelOpened()
                    panel = .search
                }
            },
            end: { model.endSearch() }
        )
    }

    /// A choice in a panel made: the panel and the controls go.
    private func backToReading() {
        withAnimation(.easeOut(duration: 0.2)) {
            panel = nil
            controls.hide()
        }
    }

    /// A column button's frame in the window, for its panel to grow out of.
    /// SwiftUI measures a toolbar item in its own space (about (-15, -10)
    /// for Aa), so this asks UIKit for the bar button with that title.
    private static func columnButtonFrame(titled title: String) -> CGRect? {
        func bars(in view: UIView) -> [UINavigationBar] {
            (view as? UINavigationBar).map { [$0] } ?? view.subviews.flatMap(bars)
        }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter(\.isKeyWindow)
        for window in windows {
            for item in bars(in: window).flatMap({ $0.items ?? [] }) {
                let buttons = (item.rightBarButtonItems ?? []) + item.trailingItemGroups.flatMap(\.barButtonItems)
                if let frame = buttons.first(where: { $0.title == title })?.frame(in: window) { return frame }
            }
        }
        return nil
    }

    private var showControlsButton: some View {
        Button("Show Controls", systemImage: "ellipsis") {
            withAnimation(.easeOut(duration: 0.2)) { controls.show() }
        }
        .tint(.secondary)
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
/// scrubber through the whole book, and the page numbers. Its edges line up
/// with the text's, just above the home indicator (Adam, 2026-11-03). Half
/// open, it follows the spread: the chapter and scrubber under the left
/// page, the chapter's progress under the right (`ReaderBarReadout`),
/// nothing on the hinge (decision 9). As tall as what it holds plus its
/// padding; half open both pieces take the taller one's height.
private struct ReaderProgressBar: View {
    let model: ReaderModel
    /// Where the scrubber is while it's dragged, and after it's let go until
    /// the page gets there.
    @State private var scrub: Double?
    @State private var relocationsAtRelease: Int?

    var body: some View {
        if let geometry = model.geometry,
           case let spans = model.layout.barSpans(in: geometry, bookMode: model.isBookMode),
           let first = spans.first, let last = spans.last {
            Group {
                if spans.count == 2 {
                    HStack(spacing: last.lowerBound - first.upperBound) {
                        glass { scrubber }
                            .frame(width: first.upperBound - first.lowerBound)
                        glass { readout }
                            .frame(width: last.upperBound - last.lowerBound)
                    }
                } else {
                    glass {
                        VStack(alignment: .leading, spacing: 2) {
                            scrubber
                            numbers
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // The bar's bottom on the home indicator's edge.
            .frame(width: last.upperBound - first.lowerBound, height: ReaderLayout.barBottom(in: geometry), alignment: .bottom)
            .offset(x: first.lowerBound)
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

    /// Under the right page in book mode.
    @ViewBuilder private var readout: some View {
        let place = place
        switch ReaderBarReadout.standard {
        case .chapter:
            if let chapter = ReaderChapterProgress(place: place, toc: model.toc) {
                // Laid out as the scrubber is, so the line is level with
                // its track on the left.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chapter.text)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let pages = place.pages(spread: true) {
                            Text(pages)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                    }
                    // The system slider without its thumb, so the line has
                    // the scrubber's colours on the glass (a ProgressView
                    // draws a deeper blue there).
                    Slider(value: .constant(chapter.fraction), in: 0...1)
                        .controlSize(.mini)
                        .sliderThumbVisibility(.hidden)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityElement(children: .combine)
            } else {
                numbers.frame(maxWidth: .infinity, alignment: .leading)
            }
        case .pages:
            numbers.frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.vertical, 12)
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// The chapter and page in each page's bottom margin, outside the text
/// (decision 7). Under the fold's cross-fade; hidden while a page turns,
/// whose pictures carry each page's own (`ReaderTurn`).
struct ReaderFooter: View {
    let model: ReaderModel

    var body: some View {
        if model.phase == .open, let geometry = model.geometry {
            ReaderFooterLines(
                place: ReaderPlace(chapter: model.chapter, location: model.location, fraction: model.position?.fraction ?? 0),
                layout: model.layout, geometry: geometry
            )
        }
    }
}

/// Each page's footer line for `place`: one line per page, the chapter on
/// the first and the numbers on the last, so a spread splits at the gutter.
/// Ignores touches.
struct ReaderFooterLines: View {
    let place: ReaderPlace
    let layout: ReaderLayout
    let geometry: ReaderGeometry

    var body: some View {
        if let columns = layout.textColumns(inReaderWidth: Double(geometry.size.width)),
           let first = columns.first, let last = columns.last {
            let spread = columns.count > 1
            let centre = Double(geometry.size.height) - layout.bottomInset - ReaderLayout.verticalMargin / 2
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
