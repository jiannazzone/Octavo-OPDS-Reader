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
        let list = highlightsForPage
        guard phase == .open, !isFixedLayout, list != sentHighlights else { return }
        sentHighlights = list
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
