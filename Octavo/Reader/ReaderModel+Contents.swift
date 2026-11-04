import Foundation
import OctavoKit
import WebKit

/// A line of the Contents panel (decision 17).
nonisolated struct ReaderContentsRow: Identifiable, Equatable, Sendable {
    let id: Int
    let label: String
    let depth: Int
    /// Where the entry starts, as the footer counts pages.
    let page: Int?
    let href: String?
    let fraction: Double?
}

extension ReaderModel {
    /// The contents, with page numbers for the current layout's count.
    var contentsRows: [ReaderContentsRow] {
        let total = location?.total
        return toc.enumerated().map { index, entry in
            ReaderContentsRow(
                id: index,
                label: entry.label,
                depth: entry.depth ?? 0,
                page: entry.fraction.flatMap { Self.page(at: $0, total: total) },
                href: entry.href,
                fraction: entry.fraction
            )
        }
    }

    /// The entry the page is in: foliate's own answer, else the last one
    /// starting at or before the page.
    var currentContentsRow: Int? {
        if let href = relocation?.tocHref, let index = toc.firstIndex(where: { $0.href == href }) { return index }
        guard let fraction = relocation?.pageFraction ?? relocation?.fraction else { return nil }
        return toc.lastIndex { ($0.fraction ?? .infinity) <= fraction + 1e-9 }
    }

    /// The page number at `fraction`, counted as the footer counts.
    static func page(at fraction: Double, total: Int?) -> Int? {
        ReaderPlace(fraction: fraction, toc: [], total: total).first
    }

    func goTo(_ row: ReaderContentsRow) {
        if let href = row.href {
            goTo(target: href)
        } else if let fraction = row.fraction {
            goTo(fraction: fraction)
        }
    }

    func goTo(_ bookmark: LocalBookmark) {
        goTo(target: bookmark.cfi)
    }

    // MARK: Chapter buttons

    var chapterSkip: ReaderChapterSkip {
        let page = ReaderPlace(chapter: nil, location: location, fraction: shownFraction)
        var isOnFirstEntry = false
        if let start = toc.first?.fraction.flatMap({ Self.page(at: $0, total: location?.total) }), let first = page.first, let last = page.last {
            isOnFirstEntry = (first...last).contains(start)
        }
        return ReaderChapterSkip(count: toc.count, current: currentContentsRow, isOnFirstEntry: isOnFirstEntry)
    }

    /// Goes to the first of the buttons' places that moves the page.
    func skipChapter(_ direction: ReaderChapterSkip.Direction) {
        guard phase == .open, !isSkippingChapter else { return }
        isSkippingChapter = true
        Task {
            defer { isSkippingChapter = false }
            let rows = contentsRows
            for index in chapterSkip.targets(direction) where rows.indices.contains(index) {
                if await goToAndSeeIfThePageMoved(rows[index]) { return }
            }
        }
    }

    private func goToAndSeeIfThePageMoved(_ row: ReaderContentsRow) async -> Bool {
        let before = relocation?.startCFI ?? relocation?.cfi
        let count = relocationCount
        if let href = row.href {
            _ = try? await page.callJavaScript("return await window.octavo.goTo(target)", arguments: ["target": href])
        } else if let fraction = row.fraction {
            _ = try? await page.callJavaScript("return await window.octavo.goToFraction(fraction)", arguments: ["fraction": fraction])
        } else {
            return false
        }
        // The relocations come after the call does, and a page settling on a
        // spread can take a moment and report more than once.
        var last = count
        var quiet = 0
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(20))
            quiet = relocationCount == last ? quiet + 1 : 0
            last = relocationCount
            if last != count, quiet >= 3 { break }
        }
        return (relocation?.startCFI ?? relocation?.cfi) != before
    }

    /// The Contents panel opening: what's in the section on screen placed
    /// again by its layout, so the page numbers match the footer after a
    /// font, margin or fold change.
    func placeOnScreen() async {
        guard phase == .open else { return }
        if !toc.isEmpty,
           let entries = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(toc)),
           let placed = try? await page.callJavaScript("return await window.octavo.contentsOnScreen(entries)", arguments: ["entries": entries]),
           let data = try? JSONSerialization.data(withJSONObject: placed),
           let refined = try? JSONDecoder().decode([ReaderMessage.TOCEntry].self, from: data),
           refined.count == toc.count {
            contentsPlaced(refined)
        }
        let list = bookmarks.list
        guard !list.isEmpty,
              let fractions = try? await page.callJavaScript("return await window.octavo.bookmarksOnScreen(cfis)", arguments: ["cfis": list.map(\.cfi)]) as? [Any],
              fractions.count == list.count
        else { return }
        var placed: [LocalBookmark.ID: Double] = [:]
        for (bookmark, fraction) in zip(list, fractions) {
            if let fraction = fraction as? Double { placed[bookmark.id] = fraction }
        }
        bookmarks.place(placed)
    }

    // MARK: Search

    /// Searches for what's typed, if it's worth searching.
    func runSearch(submitted: Bool) {
        guard phase == .open else { return }
        guard let text = search.searchable(submitted: submitted) else {
            // Too short to search as you type: the last results go, unless
            // they're this query's own (one letter, searched on Return).
            if search.query.trimmingCharacters(in: .whitespacesAndNewlines) != search.searched { clearSearch() }
            return
        }
        guard text != search.searched || submitted && !search.isSearching && search.matches.isEmpty else { return }
        hideMatch()
        let token = search.begin(text)
        call("return await window.octavo.search(query, token)", arguments: ["query": text, "token": token])
    }

    /// The field emptied.
    func clearSearch() {
        hideMatch()
        search.clear()
        call("return await window.octavo.cancelSearch()")
    }

    /// Goes to a match and highlights it.
    func showMatch(_ index: Int) {
        guard search.matches.indices.contains(index) else { return }
        search.show(index)
        call("return await window.octavo.showMatch(cfi)", arguments: ["cfi": search.matches[index].cfi])
    }

    /// ✕ on the step bar: the highlight goes and the search with it.
    func endSearch() {
        hideMatch()
        search.end()
        call("return await window.octavo.cancelSearch()")
    }

    private func hideMatch() {
        guard search.isStepping else { return }
        call("return await window.octavo.showMatch(null)")
    }

    // MARK: Bookmarks

    /// The page's Bookmark button.
    func toggleBookmark() {
        guard phase == .open else { return }
        if bookmarks.pageIsBookmarked {
            bookmarks.toggle(pageStart: nil, place: nil)
            return
        }
        guard let relocation, relocation.blankPage != true, let cfi = relocation.startCFI ?? relocation.cfi else { return }
        Task {
            let place = await describe(cfi) ?? BookmarkPlace(fraction: relocation.shownFraction, chapter: relocation.tocLabel, excerpt: nil)
            bookmarks.toggle(pageStart: cfi, place: place)
        }
    }

    /// After the book opens: synced with the server, every bookmark placed,
    /// and the page's checked.
    func refreshBookmarks() async {
        await bookmarks.refresh()
        for bookmark in bookmarks.undescribed {
            if let place = await describe(bookmark.cfi) { bookmarks.describe(bookmark.id, as: place) }
        }
        await updateBookmarkedPage()
    }

    /// Which bookmarks the visible page holds. A page turned since the
    /// question was asked gets its own answer.
    func updateBookmarkedPage() async {
        let list = bookmarks.list
        guard !list.isEmpty, phase == .open else {
            bookmarks.setOnPage([])
            return
        }
        let asked = relocationCount
        let flags = (try? await page.callJavaScript("return await window.octavo.onPage(cfis)", arguments: ["cfis": list.map(\.cfi)])) as? [Bool]
        guard asked == relocationCount, let flags, flags.count == list.count else { return }
        bookmarks.setOnPage(Set(zip(list, flags).filter(\.1).map(\.0.id)))
    }

    func describe(_ cfi: String) async -> BookmarkPlace? {
        guard let result = try? await page.callJavaScript("return await window.octavo.describe(cfi)", arguments: ["cfi": cfi]) as? [String: Any] else {
            return nil
        }
        return BookmarkPlace(
            fraction: result["fraction"] as? Double,
            chapter: result["chapter"] as? String,
            excerpt: result["excerpt"] as? String
        )
    }
}
