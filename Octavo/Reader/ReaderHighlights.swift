import Foundation
import OctavoKit
import os

/// One book's highlights (#125): kept on the iPhone, and synced with
/// BookOrbit for its books. Changes show at once and sync behind; a change
/// that can't reach the server waits for the next refresh. Quotes and notes
/// are never logged.
@Observable
final class ReaderHighlights {
    /// Everything kept, removals still to sync included.
    private(set) var all: [LocalHighlight]

    @ObservationIgnored let bookID: String
    @ObservationIgnored private let store: HighlightStore
    @ObservationIgnored private let sync: (any HighlightSync)?
    /// Highlights with a send on its way, so a refresh doesn't send twice.
    @ObservationIgnored private var sending: Set<LocalHighlight.ID> = []
    @ObservationIgnored private let log = Logger(subsystem: "com.ianazzone.ereader", category: "Highlights")

    init(bookID: String, store: HighlightStore = HighlightStore(), sync: (any HighlightSync)? = nil) {
        self.bookID = bookID
        self.store = store
        self.sync = sync
        all = store.items(forBook: bookID)
    }

    /// The list, in the book's order: the ones this file has.
    var list: [LocalHighlight] {
        all.filter { !$0.isRemoved && $0.cfi != nil }.sorted {
            ($0.fraction ?? .infinity, $0.createdAt) < ($1.fraction ?? .infinity, $1.createdAt)
        }
    }

    /// The server's highlights this file doesn't have ("Not Found in This
    /// File").
    var notFound: [LocalHighlight] {
        all.filter { !$0.isRemoved && $0.cfi == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Highlights the list can't place yet (synced from elsewhere, or moved).
    var undescribed: [LocalHighlight] { list.filter { !$0.isDescribed } }

    func highlight(_ id: LocalHighlight.ID) -> LocalHighlight? {
        all.first { $0.id == id && !$0.isRemoved }
    }

    /// The highlight drawn for a range.
    func highlight(cfi: String) -> LocalHighlight? {
        all.first { $0.cfi == cfi && !$0.isRemoved }
    }

    @discardableResult
    func add(cfi: String, text: String, color: String, chapter: String? = nil, fraction: Double? = nil) -> LocalHighlight {
        let highlight = LocalHighlight(cfi: cfi, text: text, color: color, chapter: chapter, fraction: fraction)
        all.append(highlight)
        save()
        Task { await send(highlight.id) }
        return highlight
    }

    func recolor(_ id: LocalHighlight.ID, to color: String) {
        edit(id, .color) { $0.color = color }
    }

    /// An empty note clears it.
    func setNote(_ id: LocalHighlight.ID, to note: String?) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        edit(id, .note) { $0.note = trimmed?.isEmpty == false ? trimmed : nil }
    }

    func remove(_ id: LocalHighlight.ID) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        // An add on its way removes it once the server has answered.
        if all[index].remoteID == nil, !sending.contains(id) {
            all.remove(at: index)
        } else {
            all[index].isRemoved = true
        }
        save()
        Task { await send(id) }
    }

    func describe(_ id: LocalHighlight.ID, chapter: String?, fraction: Double?) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].fraction = fraction
        all[index].chapter = chapter ?? all[index].chapter
        save()
    }

    /// Highlights placed again in the current layout.
    func place(_ fractions: [LocalHighlight.ID: Double]) {
        var changed = false
        for (id, fraction) in fractions {
            guard let index = all.firstIndex(where: { $0.id == id }), all[index].fraction != fraction else { continue }
            all[index].fraction = fraction
            changed = true
        }
        if changed { save() }
    }

    /// The server's highlights merged in and changes made offline sent.
    func refresh() async {
        guard let sync else { return }
        let remote: [SyncedHighlight]
        do {
            remote = try await sync.highlights()
        } catch {
            log.error("Couldn't fetch highlights: \(error)")
            return
        }
        let result = HighlightReconciliation.reconcile(local: all, remote: remote)
        // One whose add is still on its way stays, so its answer finds it.
        let inFlight = all.filter { highlight in sending.contains(highlight.id) && !result.highlights.contains { $0.id == highlight.id } }
        all = result.highlights + inFlight
        save()
        let waiting = result.toAdd + result.toUpdate + all.filter(\.isRemoved).map(\.id)
        for id in waiting where !sending.contains(id) { await send(id) }
    }

    private func edit(_ id: LocalHighlight.ID, _ field: LocalHighlight.Field, _ change: (inout LocalHighlight) -> Void) {
        guard let index = all.firstIndex(where: { $0.id == id && !$0.isRemoved }) else { return }
        let before = all[index]
        change(&all[index])
        guard all[index] != before else { return }
        all[index].unsent.insert(field)
        all[index].editedAt = .now
        save()
        Task { await send(id) }
    }

    /// Sends whatever one highlight has waiting: its add, its changes or its
    /// removal. Changes made while one is on its way go after it.
    private func send(_ id: LocalHighlight.ID) async {
        guard let sync, !sending.contains(id) else { return }
        sending.insert(id)
        defer { sending.remove(id) }
        // Each pass sends one thing; three covers an add, then a change made
        // meanwhile, then a removal made meanwhile.
        for _ in 0..<3 {
            guard let highlight = all.first(where: { $0.id == id }) else { return }
            do {
                if highlight.isRemoved {
                    if let remoteID = highlight.remoteID { try await sync.remove(id: remoteID) }
                    all.removeAll { $0.id == id }
                } else if highlight.remoteID == nil, let new = highlight.new {
                    let synced = try await sync.add(new)
                    answered(id, sent: highlight, with: synced, fields: [.color, .note])
                } else if let remoteID = highlight.remoteID, !highlight.unsent.isEmpty {
                    do {
                        let synced = try await sync.update(id: remoteID, highlight.edit)
                        answered(id, sent: highlight, with: synced, fields: highlight.unsent)
                    } catch HighlightSyncError.gone {
                        // Deleted elsewhere: that wins.
                        all.removeAll { $0.id == id }
                    }
                } else {
                    return
                }
                save()
            } catch {
                log.error("Couldn't sync a highlight: \(error)")
                return
            }
        }
    }

    /// The server's answer taken in. A field changed again since `sent` was
    /// sent stays unsent.
    private func answered(_ id: LocalHighlight.ID, sent: LocalHighlight, with synced: SyncedHighlight, fields: Set<LocalHighlight.Field>) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].remoteID = synced.id
        all[index].syncedUpdatedAt = synced.updatedAt
        for field in fields {
            let unchanged = switch field {
            case .color: all[index].color == sent.color
            case .note: all[index].note == sent.note
            }
            if unchanged { all[index].unsent.remove(field) }
        }
        if all[index].unsent.isEmpty { all[index].editedAt = nil }
        // Kept before anything else can fail, so what's left is retried
        // rather than forgotten.
        save()
    }

    private func save() {
        do {
            try store.save(all, forBook: bookID)
        } catch {
            log.error("Couldn't save highlights: \(error)")
        }
    }
}
