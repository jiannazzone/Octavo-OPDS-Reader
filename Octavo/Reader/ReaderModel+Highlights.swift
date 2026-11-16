import OctavoKit
import WebKit

/// Highlights on the page (#125): drawn by the bridge, kept and synced by
/// `ReaderHighlights`. Fixed-layout books leave them out: foliate has nothing
/// to draw them on there.
extension ReaderModel {
    /// How many places are worked out per call, so a closing reader stops
    /// between batches rather than parsing the whole book.
    static let describeBatch = 40

    /// What the page draws: every highlight this file has, in a colour it
    /// can draw.
    var highlightsForPage: [[String: String]] {
        highlights.list.compactMap { highlight in
            highlight.cfi.map { ["cfi": $0, "color": HighlightPalette.drawable(highlight.color)] }
        }
    }

    func sendHighlights() {
        dropGoneHighlights()
        let list = highlightsForPage
        guard phase == .open, !isFixedLayout, list != sentHighlights else { return }
        sentHighlights = list
        highlightsOnPageSoon()
        call("return await window.octavo.setHighlights(list)", arguments: ["list": highlightsForPage])
    }

    /// The selection highlighted in `color`; its bar comes up.
    func highlightSelection(color: String) async {
        guard phase == .open, !isFixedLayout,
              let taken = try? await page.callJavaScript("return await window.octavo.takeSelection()") as? [String: Any],
              let cfi = taken["cfi"] as? String, let text = taken["text"] as? String
        else { return }
        let highlight = highlights.add(cfi: cfi, text: text, color: color, chapter: relocation?.tocLabel, fraction: shownFraction)
        highlightBar = highlight.id
        await describeHighlights([highlight])
    }

    /// Synced with the server, then every highlight placed for the list.
    func refreshHighlights() async {
        guard phase == .open, !isFixedLayout else { return }
        await highlights.refresh()
        await describeHighlights(highlights.undescribed)
    }

    /// Their chapters and where they fall, a batch at a time.
    func describeHighlights(_ list: [LocalHighlight]) async {
        var remaining = list.compactMap { highlight in highlight.cfi.map { (highlight.id, $0) } }
        while !remaining.isEmpty, phase == .open {
            let batch = remaining.prefix(Self.describeBatch)
            remaining.removeFirst(batch.count)
            guard let places = try? await page.callJavaScript("return await window.octavo.describeAll(cfis)", arguments: ["cfis": batch.map(\.1)]) as? [Any],
                  places.count == batch.count
            else { return }
            var described: [LocalHighlight.ID: (chapter: String?, fraction: Double?)] = [:]
            for ((id, _), place) in zip(batch, places) {
                guard let place = place as? [String: Any] else { continue }
                described[id] = (place["chapter"] as? String, place["fraction"] as? Double)
            }
            highlights.describe(described)
        }
    }
}

// MARK: The bar

extension ReaderModel {
    /// Text is selected, or a highlight was just made: the bar is up.
    var showsHighlightBar: Bool {
        phase == .open && !isFixedLayout && (selectionBox != nil || highlightBar.flatMap(highlights.highlight) != nil)
    }

    /// The highlight the bar acts on, once made.
    var barHighlight: LocalHighlight? {
        highlightBar.flatMap(highlights.highlight)
    }

    /// A colour in the bar: highlights the selection, or recolours what it
    /// just highlighted.
    func pickHighlightColor(_ hex: String) async {
        if let highlight = barHighlight {
            highlights.recolor(highlight.id, to: hex)
        } else {
            await highlightSelection(color: hex)
        }
    }

    /// Note in the bar: the selection highlighted in yellow first, if it
    /// isn't yet. The highlight, for its note's sheet.
    func highlightForNote() async -> LocalHighlight.ID? {
        if barHighlight == nil { await highlightSelection(color: LocalHighlight.defaultColor) }
        return barHighlight?.id
    }

    /// Trash in the bar: the highlight goes, and the bar with it.
    func removeBarHighlight() {
        guard let highlight = barHighlight else { return }
        highlights.remove(highlight.id)
        highlightBar = nil
    }
}

// MARK: The card

extension ReaderModel {
    /// A highlight tapped: its card comes up, in the footnote card's place,
    /// and anything else over the page goes.
    func openHighlightCard(cfi: String, box: CGRect?) {
        guard let highlight = highlights.highlight(cfi: cfi), let box else { return }
        closeNote("a highlight")
        highlightBar = nil
        onControlsTap?("dismiss")
        tappedHighlightMark = ReaderNote.Mark(x: box.minX, y: box.minY, width: box.width, height: box.height)
        tappedHighlight = highlight.id
    }

    var cardHighlight: LocalHighlight? {
        tappedHighlight.flatMap(highlights.highlight)
    }

    /// A highlight deleted elsewhere (a sync) takes its bar, card and note
    /// sheet with it.
    func dropGoneHighlights() {
        if highlightBar != nil, barHighlight == nil { highlightBar = nil }
        if tappedHighlight != nil, cardHighlight == nil { tappedHighlight = nil }
        if let id = noteSheet, highlights.highlight(id) == nil { noteSheet = nil }
    }

    func closeHighlightCard() {
        tappedHighlight = nil
    }

    func deleteCardHighlight() {
        guard let highlight = cardHighlight else { return }
        highlights.remove(highlight.id)
        tappedHighlight = nil
    }
}

// MARK: VoiceOver

extension ReaderModel {
    /// Asks once the page has settled: a jump reports its place before its
    /// page is laid out where it lands.
    func highlightsOnPageSoon() {
        highlightsOnPageCheck?.cancel()
        highlightsOnPageCheck = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await updateHighlightsOnPage()
        }
    }

    /// Which highlights start on the visible page. A page turned since the
    /// question was asked gets its own answer.
    func updateHighlightsOnPage() async {
        let list = highlights.list.compactMap { highlight in highlight.cfi.map { (highlight.id, $0) } }
        guard !list.isEmpty, phase == .open, !isFixedLayout else {
            if !highlightsOnPage.isEmpty { highlightsOnPage = [] }
            return
        }
        let asked = relocationCount
        guard let boxes = try? await page.callJavaScript("return await window.octavo.highlightBoxes(cfis)", arguments: ["cfis": list.map(\.1)]) as? [Any],
              asked == relocationCount, boxes.count == list.count
        else { return }
        highlightsOnPage = zip(list, boxes).compactMap { item, box in
            guard let box = box as? [String: Any], let x = box["x"] as? Double, let y = box["y"] as? Double,
                  let width = box["width"] as? Double, let height = box["height"] as? Double
            else { return nil }
            return (item.0, ReaderNote.Mark(x: x, y: y, width: width, height: height))
        }
    }

    /// VoiceOver's action for a highlight on the page: its card.
    func openHighlightCard(_ id: LocalHighlight.ID) {
        guard let onPage = highlightsOnPage.first(where: { $0.id == id }), let cfi = highlights.highlight(id)?.cfi else { return }
        let mark = onPage.mark
        openHighlightCard(cfi: cfi, box: CGRect(x: mark.x, y: mark.y, width: mark.width, height: mark.height))
    }
}
