import Foundation
import OctavoKit
import Testing
@testable import Octavo

/// A backend that keeps highlights in memory and records what it's sent.
private actor MemoryHighlightSync: HighlightSync {
    var remote: [SyncedHighlight]
    private(set) var added: [NewHighlight] = []
    private(set) var edits: [HighlightEdit] = []
    private(set) var removed: [String] = []
    /// Fails every call, as offline.
    var offline = false
    /// How long a fetch takes.
    var fetchTime: Duration = .zero
    private var nextID = 100
    private var clock = Date(timeIntervalSince1970: 1_000)

    init(_ remote: [SyncedHighlight] = []) {
        self.remote = remote
    }

    func setOffline(_ offline: Bool) { self.offline = offline }

    func setFetchTime(_ time: Duration) { fetchTime = time }

    func deleteElsewhere(_ id: String) { remote.removeAll { $0.id == id } }

    func highlights() async throws -> [SyncedHighlight] {
        if offline { throw URLError(.notConnectedToInternet) }
        let list = remote
        if fetchTime > .zero { try await Task.sleep(for: fetchTime) }
        return list
    }

    func add(_ highlight: NewHighlight) async throws -> SyncedHighlight {
        if offline { throw URLError(.notConnectedToInternet) }
        nextID += 1
        clock += 1
        let synced = SyncedHighlight(id: String(nextID), cfi: highlight.cfi, text: highlight.text, color: highlight.color, note: highlight.note, updatedAt: clock)
        remote.append(synced)
        added.append(highlight)
        return synced
    }

    func update(id: String, _ edit: HighlightEdit) async throws -> SyncedHighlight {
        if offline { throw URLError(.notConnectedToInternet) }
        guard let index = remote.firstIndex(where: { $0.id == id }) else { throw HighlightSyncError.gone }
        clock += 1
        if let color = edit.color { remote[index].color = color }
        if let note = edit.note { remote[index].note = note }
        remote[index].updatedAt = clock
        edits.append(edit)
        return remote[index]
    }

    func remove(id: String) async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        remote.removeAll { $0.id == id }
        removed.append(id)
    }
}

/// One book's highlights (#125): kept on the iPhone, in the book's order,
/// and synced with BookOrbit.
@MainActor
@Suite(.temporaryFiles)
struct ReaderHighlightsTests {
    private let store = HighlightStore(directory: URL.testDirectory.appending(path: "Highlights-\(UUID().uuidString)"))
    private let cfiA = "epubcfi(/6/4!/4/38/2,/1:143,/1:150)"
    private let cfiB = "epubcfi(/6/8!/4/2,/1:0,/1:20)"

    /// Waits, up to two seconds, for the sends that edits start.
    private func until(_ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func highlightsAreKeptOnTheIPhone() {
        let highlights = ReaderHighlights(bookID: "pp", store: store)
        highlights.add(cfi: cfiA, text: "Collins", color: "#4ADE80", chapter: "Introduction", fraction: 0.03)
        let reopened = ReaderHighlights(bookID: "pp", store: store)
        #expect(reopened.list.map(\.cfi) == [cfiA])
        #expect(reopened.list.first?.color == "#4ADE80")
        #expect(reopened.list.first?.chapter == "Introduction")
    }

    @Test func theListFollowsTheBookAndKeepsTheUnfoundApart() async {
        let sync = MemoryHighlightSync([SyncedHighlight(id: "9", cfi: nil, text: "It is a truth", chapter: "Chapter 1")])
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        highlights.add(cfi: cfiB, text: "Chapter", color: "#FACC15", fraction: 0.2)
        highlights.add(cfi: cfiA, text: "Collins", color: "#FACC15", fraction: 0.03)
        await highlights.refresh()
        #expect(highlights.list.map(\.cfi) == [cfiA, cfiB])
        #expect(highlights.notFound.map(\.text) == ["It is a truth"])
    }

    @Test func aNewOneIsSentWithItsColour() async {
        let sync = MemoryHighlightSync()
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        highlights.add(cfi: cfiA, text: "Collins", color: "#F472B6")
        await until { highlights.list.first?.remoteID != nil }
        #expect(await sync.added == [NewHighlight(cfi: cfiA, text: "Collins", color: "#F472B6")])
        #expect(highlights.list.first?.remoteID == "101")
    }

    @Test func aRecolourSendsOnlyTheColour() async {
        let sync = MemoryHighlightSync()
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        let highlight = highlights.add(cfi: cfiA, text: "Collins", color: "#FACC15")
        await until { highlights.list.first?.remoteID != nil }
        highlights.recolor(highlight.id, to: "#38BDF8")
        await until { await !sync.edits.isEmpty }
        #expect(await sync.edits == [HighlightEdit(color: "#38BDF8")])
        #expect(highlights.list.first?.unsent == [])
    }

    @Test func anEmptyNoteClearsIt() async {
        let sync = MemoryHighlightSync()
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        let highlight = highlights.add(cfi: cfiA, text: "Collins", color: "#FACC15")
        await until { highlights.list.first?.remoteID != nil }
        highlights.setNote(highlight.id, to: "  A fine fool.  ")
        await until { await sync.edits.count == 1 }
        highlights.setNote(highlight.id, to: "  ")
        await until { await sync.edits.count == 2 }
        #expect(await sync.edits == [HighlightEdit(note: .some("A fine fool.")), HighlightEdit(note: .some(nil))])
        #expect(highlights.list.first?.note == nil)
    }

    // Made and changed offline: the next refresh sends the lot.
    @Test func whatWasDoneOfflineIsSentNextTime() async {
        let sync = MemoryHighlightSync()
        await sync.setOffline(true)
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        let highlight = highlights.add(cfi: cfiA, text: "Collins", color: "#FACC15")
        highlights.setNote(highlight.id, to: "Ha")
        // Both sends have failed.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(highlights.list.first?.remoteID == nil)

        await sync.setOffline(false)
        await highlights.refresh()
        #expect(await sync.added == [NewHighlight(cfi: cfiA, text: "Collins", color: "#FACC15", note: "Ha")])
        #expect(await sync.edits.isEmpty, "the add carried the note")
        #expect(highlights.list.first?.unsent == [])
    }

    @Test func aRemovalReachesTheServerAndIsThenForgotten() async {
        let sync = MemoryHighlightSync([SyncedHighlight(id: "7", cfi: cfiA, text: "Collins")])
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        await highlights.refresh()
        let synced = try! #require(highlights.list.first)

        highlights.remove(synced.id)
        #expect(highlights.list.isEmpty)
        await until { highlights.all.isEmpty }
        #expect(await sync.removed == ["7"])
        #expect(highlights.all.isEmpty)
    }

    // Deleted elsewhere wins over an edit made here.
    @Test func anEditToOneDeletedElsewhereDropsIt() async {
        let sync = MemoryHighlightSync([SyncedHighlight(id: "7", cfi: cfiA, text: "Collins")])
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        await highlights.refresh()
        await sync.deleteElsewhere("7")
        highlights.recolor(try! #require(highlights.list.first).id, to: "#38BDF8")
        await until { highlights.all.isEmpty }
        #expect(highlights.all.isEmpty)
    }

    // Highlighted while the opening refresh is still fetching: its add is
    // answered first, so the fetched list is stale and is fetched again
    // rather than taken as the highlight deleted elsewhere.
    @Test func oneMadeDuringARefreshStays() async {
        let sync = MemoryHighlightSync()
        await sync.setFetchTime(.milliseconds(150))
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        let refresh = Task { await highlights.refresh() }
        try? await Task.sleep(for: .milliseconds(20))
        highlights.add(cfi: cfiA, text: "Collins", color: "#FACC15")
        await until { highlights.list.first?.remoteID != nil }
        await refresh.value
        #expect(highlights.list.map(\.cfi) == [cfiA])
    }

    @Test func anEditMadeDuringARefreshStays() async {
        let sync = MemoryHighlightSync([SyncedHighlight(id: "7", cfi: cfiA, text: "Collins", color: "#FACC15")])
        let highlights = ReaderHighlights(bookID: "pp", store: store, sync: sync)
        await highlights.refresh()
        await sync.setFetchTime(.milliseconds(150))
        let refresh = Task { await highlights.refresh() }
        try? await Task.sleep(for: .milliseconds(20))
        highlights.recolor(try! #require(highlights.list.first).id, to: "#38BDF8")
        await until { await !sync.edits.isEmpty }
        await refresh.value
        #expect(highlights.list.first?.color == "#38BDF8")
    }

    @Test func aBookFromAnywhereElseKeepsItsHighlightsHere() async {
        let highlights = ReaderHighlights(bookID: "files-book", store: store)
        let highlight = highlights.add(cfi: cfiA, text: "Collins", color: "#FACC15")
        highlights.setNote(highlight.id, to: "Mine")
        await highlights.refresh()
        #expect(highlights.list.first?.note == "Mine")
    }
}
