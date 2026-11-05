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
    /// The book has opened your place and it's drawn: pictures of its pages
    /// for the cover's motion (`ReaderCoverMotion`), or `nil` if it couldn't
    /// open.
    var opened: (ReaderCoverPages?) -> Void = { _ in }
    /// Back was tapped: pictures of the pages as they are, for the book to
    /// close like a cover. `close` follows at once.
    var closing: (ReaderCoverPages) -> Void = { _ in }
    let close: () -> Void
    @Environment(ShellModel.self) private var shell
    // Made in `.task` rather than `init`, so SwiftUI re-creating this view
    // doesn't spin up throwaway web pages.
    @State private var model: ReaderModel?
    @State private var reportedOpen = false

    var body: some View {
        ZStack {
            if let model {
                ReaderScreen(model: model, connectionReturns: connectionReturns, tourStep: shell.tour?.step) { [closing, close] in
                    closing(model.coverPages())
                    close()
                }
                    // Once the book is open and its place has stopped moving
                    // (a restore relocates a few times as it settles).
                    .task(id: ReaderOpenedCheck(open: model.phase == .open, relocations: model.relocationCount)) {
                        guard !reportedOpen, model.phase == .open, model.relocationCount > 0 else { return }
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled, !reportedOpen else { return }
                        reportedOpen = true
                        opened(model.coverPages())
                    }
                    .onChange(of: model.phase) { _, phase in
                        guard case .failed = phase, !reportedOpen else { return }
                        reportedOpen = true
                        opened(nil)
                    }
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }
        }
        .task(id: book.reader) {
            guard model?.book != book.reader else { return }
            // A tour replayed from Settings saves nothing of its own
            // (decision 30).
            let replay = shell.tourReplayPlace
            let bookmarks = ReaderBookmarks(bookID: book.reader.id, store: replay?.bookmarks ?? BookmarkStore(), sync: bookmarkSync)
            #if DEBUG
            let cfiShape = ReaderRemote.cfiShape
            #else
            let cfiShape = ReaderMessage.CFIShape.point
            #endif
            model = ReaderModel(
                book: book.reader, store: replay?.positions ?? ReadingPositionStore(), sync: progressSync, fallback: listedPlace,
                bookmarks: bookmarks, cfiShape: cfiShape
            )
        }
        .onDisappear {
            guard let model else { return }
            // Starts at once: the page's messages about leaving the window
            // aren't far behind.
            Task.immediate {
                await model.close()
                shell.places.readerClosed()
            }
        }
    }
}

/// What `ReaderView` watches to say the book has opened.
private struct ReaderOpenedCheck: Equatable {
    var open: Bool
    var relocations: Int
}

/// The page, the column's buttons and the progress bar for one open book.
private struct ReaderScreen: View {
    let model: ReaderModel
    let connectionReturns: Int
    let close: () -> Void
    @Environment(ShellModel.self) private var shell
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
    /// The progress bar's height, for the way back to sit above it.
    @State private var barHeight = 0.0
    /// The sheet's height along the bottom of one page, for the tour's card.
    @State private var sheetHeight: Double?
    @Environment(\.scenePhase) private var scenePhase

    /// `tourStep`: a reader reopened mid-tour by an unfold puts back what the
    /// step had up.
    init(model: ReaderModel, connectionReturns: Int, tourStep: TourFlow.Step?, close: @escaping () -> Void) {
        self.model = model
        self.connectionReturns = connectionReturns
        self.close = close
        var controls = ReaderControls()
        if tourStep?.showsControlsOnOpening == true { controls.show() }
        if tourStep == .makeItYours {
            controls.panelOpened()
            _panel = State(initialValue: .textAndTheme)
        }
        _controls = State(initialValue: controls)
    }

    var body: some View {
        NavigationStack {
            // The bars take the footer's place: the progress bar, the step
            // bar while stepping through search matches, or the server's place.
            ReaderWebView(model: model, showsFooter: showsFooter, hidesFooterChapter: backBarIsUp)
                .overlay { status }
                .overlay(alignment: .topLeading) {
                    if controls.showsBar, model.phase == .open {
                        ReaderProgressBar(model: model, height: $barHeight)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if backBarIsUp, let trip = model.trip, let geometry = model.geometry,
                       let left = model.layout.textColumns(inReaderWidth: Double(geometry.size.width))?.first?.lowerBound {
                        ReaderBackBar(trip: trip, back: model.goBack, stay: model.settleTrip)
                            .fixedSize()
                            .offset(x: left, y: backBarTop(in: geometry))
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: backBarIsUp)
                .animation(.easeOut(duration: 0.2), value: controls.showsBar)
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
                                ReaderServerPlaceBar(
                                    place: place, server: shell.reading.flatMap { shell.library.server($0.source)?.name } ?? "BookOrbit",
                                    go: model.goToServerPlace, stay: model.keepThisPlace
                                )
                            }
                        }
                        .frame(width: max(0, right - left))
                        .padding(.leading, left)
                        .padding(.bottom, max(geometry.safeArea.bottom, 12) + 4 + (stacksOverBackBar ? ReaderBackBar.height + 6 : 0))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: footerBar)
                .overlay(alignment: .topLeading) {
                    if let panel, model.phase == .open, let geometry = model.geometry {
                        let fold = model.layout.columns == 2 ? model.layout.fold : nil
                        ReaderPanelFrame(geometry: geometry, fold: fold, source: panelButtonFrame, fillsSheet: panel != .textAndTheme, keyboard: keyboard) {
                            Group {
                                switch panel {
                                case .textAndTheme:
                                    ReaderTextPanel(appearance: $appearance, darkMode: darkMode, showsAll: fold != nil, close: closePanel)
                                case .contents:
                                    contentsPanel
                                case .search:
                                    searchPanel
                                }
                            }
                            .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { sheetHeight = $0 }
                        }
                        // Another panel grows out of its own button.
                        .id(panel)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let note = model.note, model.phase == .open, let geometry = model.geometry {
                        ReaderNoteLayer(
                            note: note,
                            placement: ReaderNotePlacement(mark: note.mark, layout: model.layout, geometry: geometry),
                            theme: appearance.theme(darkMode: darkMode),
                            goToNote: model.goToNote,
                            close: { model.closeNote("✕") },
                            swiped: model.noteSwiped
                        )
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.note)
                .overlay(alignment: .topLeading) {
                    if let step = shell.tour?.step, model.phase == .open, shell.coverMotion == nil, let geometry = model.geometry {
                        let onOnePage = panel != nil && !(model.layout.columns == 2 && model.layout.fold != nil)
                        TourCardSlot(step: step, geometry: geometry, layout: model.layout, sheetHeight: onOnePage ? sheetHeight : nil)
                            .id(step)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: shell.tour?.step)
                .ignoresSafeArea()
                .accessibilityAction(named: Text(controls.showsBar ? "Hide Controls" : "Show Controls")) {
                    withAnimation { controls.toggle() }
                }
                .toolbar { buttons }
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
        .onChange(of: scenePhase == .background, initial: true) { _, isInBackground in
            model.isInBackground = isInBackground
        }
        .onChange(of: controls.coversPage || panel != nil || model.note != nil, initial: true) { _, covers in
            model.coversPage = covers
        }
        .onChange(of: panel) { _, panel in
            if panel != nil { model.closeNote("a panel") }
            if panel == .contents { Task { await model.placeOnScreen() } }
        }
        // The bar would run under a note.
        .onChange(of: controls.showsBar) { _, shows in
            if shows { model.closeNote("the bar") }
        }
        // The tour's Turn the page: the page lifts every few seconds until it's
        // turned. Not while something covers it: a tap would only close that.
        .task(id: hintsPageTurn) {
            guard hintsPageTurn else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                await model.playTurnHint()
                try? await Task.sleep(for: .seconds(1.3))
            }
        }
        .onChange(of: tourReaderState, initial: true) { _, state in
            shell.tourEvent(.reader(state))
        }
        .onChange(of: shell.tour?.step) { _, step in
            // Done: on to the last card, with the page clear.
            if step == .addYourBooks { backToReading() }
            // A step may start with what it asks for already done.
            shell.tourEvent(.reader(tourReaderState))
            if let card = shell.tour?.step.card {
                AccessibilityNotification.Announcement("\(card.title). \(card.message)").post()
            }
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
            model.onPageTurned = { [weak shell] in shell?.tourEvent(.pageTurned) }
        }
        #if DEBUG
        .readerRemote(model, back: close)
        #endif
    }

    private var darkMode: Bool { systemColorScheme == .dark }

    /// The way back stays up with the controls hidden (decision 33). Not
    /// under a panel or a note, or on one page while Search's bar has the
    /// footer's place.
    private var backBarIsUp: Bool {
        guard model.trip != nil, panel == nil, model.note == nil, shell.tour == nil, model.phase == .open else { return false }
        return !(model.search.isStepping && model.layout.columns != 2)
    }

    /// On one page, BookOrbit's capsule stacks above the way back (decision
    /// 33). Open, they sit one under each page.
    private var stacksOverBackBar: Bool {
        guard backBarIsUp, model.layout.columns != 2, case .serverPlace = footerBar else { return false }
        return true
    }

    /// The bars take the footer's place, except that on one page the way back
    /// keeps the numbers beside it, with BookOrbit's capsule above.
    private var showsFooter: Bool {
        !controls.showsBar && (footerBar == nil || stacksOverBackBar)
    }

    /// In the footer's place, or just above the progress bar while it's up.
    private func backBarTop(in geometry: ReaderGeometry) -> Double {
        if controls.showsBar {
            return ReaderLayout.barBottom(in: geometry) - barHeight - 8 - ReaderBackBar.height
        }
        return Double(geometry.size.height) - model.layout.bottomInset - ReaderLayout.verticalMargin / 2 - ReaderBackBar.height / 2
    }

    private var hintsPageTurn: Bool {
        shell.tour?.step == .turnThePage && model.phase == .open && shell.coverMotion == nil && !controls.coversPage && panel == nil
    }

    /// What the tour's steps in the book look at.
    private var tourReaderState: TourFlow.ReaderState {
        TourFlow.ReaderState(barVisible: controls.showsBar, buttonsVisible: controls.buttonsVisible, textPanelOpen: panel == .textAndTheme)
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
        case .open, .closed:
            EmptyView()
        case .failed(let message):
            ContentUnavailableView("Couldn’t Open", systemImage: "exclamationmark.triangle", description: Text(message))
                .background(Color(.systemBackground))
        }
    }

    /// The column's buttons (frame 08). Back is always up, on its own, and
    /// as quiet as "…" while the rest are hidden (Adam, 2026-11-04). Skip
    /// takes its place in the tour, as the way out. Two `if`s: with an `else`,
    /// Skip's word comes up blank.
    @ToolbarContentBuilder private var buttons: some ToolbarContent {
        if shell.tour != nil {
            ToolbarItem(placement: .topBarTrailing) {
                TourSkipButton { shell.skipTour() }
            }
        }
        if shell.tour == nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Back", systemImage: "chevron.backward", action: close)
                    .tint(controls.buttonsVisible ? nil : Color.secondary)
            }
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        if showsControlsButton, !controls.buttonsVisible {
            ToolbarItem(placement: .topBarTrailing) { showControlsButton }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if controls.buttonsVisible {
                panelButton(.contents, title: "Contents", systemImage: "list.bullet")
                panelButton(.textAndTheme, title: "Text and Theme", systemImage: "textformat.size", lit: shell.tour?.step.litButton == .textAndTheme)
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
    /// `lit`: the tour asks for this button next, so it's blue, as it's named
    /// on the card (Adam, 2026-11-03).
    private func panelButton(_ selected: ReaderPanel, title: LocalizedStringResource, systemImage: String, lit: Bool = false) -> some View {
        Button(String(localized: title), systemImage: systemImage) {
            guard panel != selected else {
                closePanel()
                return
            }
            panelButtonFrame = Self.columnButtonFrame(titled: String(localized: title))
            withAnimation(ReaderPanel.animation) {
                if panel == nil { controls.panelOpened() }
                panel = selected
            }
        }
        .tint(panel == selected || lit ? .accentColor : nil)
        .accessibilityAddTraits(panel == selected ? .isSelected : [])
    }

    /// A panel's ✕, or its button again: back to the controls as they were.
    private func closePanel() {
        withAnimation(ReaderPanel.animation) {
            panel = nil
            controls.panelClosed()
        }
    }

    private var contentsPanel: some View {
        ReaderContentsPanel(
            rows: model.contentsRows,
            current: model.currentContentsRow,
            bookmarks: model.bookmarks.list,
            page: { [total = model.location?.total] in ReaderModel.page(at: $0, total: total) },
            goToRow: { row in
                model.jump(to: row)
                backToReading()
            },
            goToBookmark: { bookmark in
                model.jump(to: bookmark)
                backToReading()
            },
            remove: { model.bookmarks.remove($0) },
            close: closePanel
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
            },
            close: closePanel
        )
    }

    /// What takes the footer's place while no panel or progress bar is up.
    private enum FooterBar: Equatable {
        case search
        case serverPlace(ReaderServerPlace)
    }

    private var footerBar: FooterBar? {
        guard panel == nil, !controls.showsBar, model.note == nil, model.phase == .open else { return nil }
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
        .tint(shell.tour?.step.litButton == .showControls ? .accentColor : .secondary)
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
    @Binding var height: Double
    /// Where the scrubber is while it's dragged, and after it's let go until
    /// the page gets there.
    @State private var scrub: Double?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
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
            .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { height = $0 }
            // The bar's bottom on the home indicator's edge.
            .frame(width: last.upperBound - first.lowerBound, height: ReaderLayout.barBottom(in: geometry), alignment: .bottom)
            .offset(x: first.lowerBound)
        }
    }

    private var place: ReaderPlace {
        if let scrub {
            return ReaderPlace(fraction: scrub, toc: model.toc, total: model.location?.total)
        }
        return ReaderPlace(chapter: model.chapter, location: model.location, fraction: model.shownFraction)
    }

    /// The chapter's name between its buttons (decision 35), which keep a
    /// finger's room without making the bar any taller.
    private var chapterLine: some View {
        let skip = model.chapterSkip
        return HStack(spacing: 0) {
            if skip.isAvailable { chapterButton(.back, isEnabled: skip.canGoBack) }
            Text(place.chapter ?? model.title ?? " ")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if skip.isAvailable { chapterButton(.forward, isEnabled: skip.canGoForward) }
        }
    }

    private func chapterButton(_ direction: ReaderChapterSkip.Direction, isEnabled: Bool) -> some View {
        Button {
            model.skipChapter(direction)
        } label: {
            Image(systemName: direction == .back ? "backward.end.fill" : "forward.end.fill")
                .font(.footnote)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
        .disabled(!isEnabled)
        .padding(direction == .back ? .leading : .trailing, -14)
        .padding(.vertical, -13)
        .accessibilityLabel(direction == .back ? "Previous Chapter" : "Next Chapter")
    }

    private var scrubber: some View {
        VStack(alignment: .leading, spacing: 0) {
            chapterLine
            ReaderScrubber(value: fraction, chapters: model.toc.compactMap(\.fraction), total: model.location?.total, neutral: model.trip?.placeFraction) { chapter in
                guard let scrub else { return }
                relocationsAtRelease = model.relocationCount
                if let chapter, let href = model.toc.first(where: { $0.fraction == chapter })?.href {
                    model.jump(to: href)
                } else {
                    model.jump(toFraction: scrub)
                }
            } cancelled: {
                scrub = nil
                relocationsAtRelease = nil
            }
            // A slider only redraws its fill for a new value, and a landing
            // brings none, so a new place gets a new slider. VoiceOver would
            // lose its place on it, and keeps this one.
            .id(voiceOverEnabled ? nil : model.trip?.placeFraction)
            .frame(height: 30)
            // A jump that doesn't relocate (it landed on this page, or the
            // place wouldn't open) mustn't leave the knob on it for good.
            .task(id: relocationsAtRelease) {
                guard relocationsAtRelease != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                scrub = nil
                relocationsAtRelease = nil
            }
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
            scrub ?? model.shownFraction
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
    var hidesChapter = false

    var body: some View {
        if model.phase == .open, let geometry = model.geometry {
            ReaderFooterLines(
                place: ReaderPlace(chapter: model.chapter, location: model.location, fraction: model.shownFraction),
                layout: model.layout, geometry: geometry, hidesChapter: hidesChapter
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
    /// The way back sits in the chapter's place (decision 33).
    var hidesChapter = false

    var body: some View {
        if let columns = layout.textColumns(inReaderWidth: Double(geometry.size.width)),
           let first = columns.first, let last = columns.last {
            let spread = columns.count > 1
            let centre = Double(geometry.size.height) - layout.bottomInset - ReaderLayout.verticalMargin / 2
            Group {
                if spread {
                    line(chapter: hidesChapter ? nil : place.chapter, numbers: nil, in: first, centre: centre)
                    line(chapter: nil, numbers: place.footer(spread: true), in: last, centre: centre)
                } else {
                    line(chapter: hidesChapter ? nil : place.chapter, numbers: place.footer(spread: false), in: first, centre: centre)
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
