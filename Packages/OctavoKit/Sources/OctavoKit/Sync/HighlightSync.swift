import Foundation

/// A highlight as a sync backend keeps it (#125).
public struct SyncedHighlight: Hashable, Sendable {
    public var id: String
    /// The highlighted range in the file being read. `nil` when the backend
    /// can't place it there (made on another file, or a place it couldn't
    /// convert).
    public var cfi: String?
    /// The highlighted words.
    public var text: String
    /// As the backend stores it: BookOrbit's hex, or whatever another app
    /// wrote (a name, KOReader's hex).
    public var color: String?
    public var note: String?
    public var chapter: String?
    public var updatedAt: Date?
    public var createdAt: Date?

    public init(
        id: String, cfi: String?, text: String, color: String? = nil, note: String? = nil,
        chapter: String? = nil, updatedAt: Date? = nil, createdAt: Date? = nil
    ) {
        self.id = id
        self.cfi = cfi
        self.text = text
        self.color = color
        self.note = note
        self.chapter = chapter
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

/// A new highlight on its way to the backend.
public struct NewHighlight: Hashable, Sendable {
    public var cfi: String
    public var text: String
    public var color: String
    public var note: String?
    public var chapter: String?

    public init(cfi: String, text: String, color: String, note: String? = nil, chapter: String? = nil) {
        self.cfi = cfi
        self.text = text
        self.color = color
        self.note = note
        self.chapter = chapter
    }
}

/// What changed on a highlight: only those fields are sent. A note of
/// `.some(nil)` clears it.
public struct HighlightEdit: Hashable, Sendable {
    public var color: String?
    public var note: String??

    public init(color: String? = nil, note: String?? = nil) {
        self.color = color
        self.note = note
    }

    public var isEmpty: Bool { color == nil && note == nil }
}

public enum HighlightSyncError: Error, Equatable {
    /// The backend no longer has it: it was deleted elsewhere.
    case gone
}

/// Where one book's highlights sync (#125): BookOrbit's annotations, for its
/// books. Books from anywhere else keep their highlights on the device.
public protocol HighlightSync: Sendable {
    func highlights() async throws -> [SyncedHighlight]
    func add(_ highlight: NewHighlight) async throws -> SyncedHighlight
    /// Throws `HighlightSyncError.gone` if the backend no longer has it.
    func update(id: String, _ edit: HighlightEdit) async throws -> SyncedHighlight
    /// Removing one that's already gone succeeds.
    func remove(id: String) async throws
}

/// The device's record of a highlight, synced or not.
public struct LocalHighlight: Codable, Hashable, Sendable, Identifiable {
    public enum Field: String, Codable, Hashable, Sendable {
        case color, note
    }

    public static let defaultColor = "#FACC15"

    public var id: UUID
    /// The highlighted range. `nil` for a backend's highlight this file
    /// doesn't have ("Not Found in This File").
    public var cfi: String?
    public var text: String
    public var color: String
    public var note: String?
    public var createdAt: Date
    /// The backend's ID, once the backend has it.
    public var remoteID: String?
    /// Removed here while the backend still has it; the removal is retried.
    public var isRemoved: Bool
    /// Changed here and not sent yet.
    public var unsent: Set<Field>
    /// When those changes were made, to weigh them against the backend's.
    public var editedAt: Date?
    /// The backend's `updatedAt` when last seen: a different one means it
    /// changed elsewhere since.
    public var syncedUpdatedAt: Date?
    /// The chapter: the reader's name for it once placed, else the
    /// backend's.
    public var chapter: String?
    /// Where it falls in the book, 0...1, worked out by the reader. Never
    /// synced.
    public var fraction: Double?

    public init(
        id: UUID = UUID(), cfi: String?, text: String, color: String = LocalHighlight.defaultColor, note: String? = nil,
        createdAt: Date = .now, remoteID: String? = nil, isRemoved: Bool = false, unsent: Set<Field> = [],
        editedAt: Date? = nil, syncedUpdatedAt: Date? = nil, chapter: String? = nil, fraction: Double? = nil
    ) {
        self.id = id
        self.cfi = cfi
        self.text = text
        self.color = color
        self.note = note
        self.createdAt = createdAt
        self.remoteID = remoteID
        self.isRemoved = isRemoved
        self.unsent = unsent
        self.editedAt = editedAt
        self.syncedUpdatedAt = syncedUpdatedAt
        self.chapter = chapter
        self.fraction = fraction
    }

    /// Placed, so the list can show its page.
    public var isDescribed: Bool { fraction != nil }

    /// Has something still to send: its add, a change or its removal.
    public var isWaiting: Bool {
        isRemoved || !unsent.isEmpty || (remoteID == nil && cfi != nil)
    }

    /// The unsent changes, as the backend takes them.
    public var edit: HighlightEdit {
        HighlightEdit(
            color: unsent.contains(.color) ? color : nil,
            note: unsent.contains(.note) ? .some(note) : nil
        )
    }

    /// What a new one sends.
    public var new: NewHighlight? {
        cfi.map { NewHighlight(cfi: $0, text: text, color: color, note: note, chapter: chapter) }
    }
}

/// Brings the device's highlights and the backend's together.
///
/// - The backend's list is the truth for highlights it has seen: one it no
///   longer has was deleted elsewhere and goes, edits and all; one the
///   device doesn't know was made elsewhere.
/// - The backend's range, words and chapter always win. For the colour and
///   the note, changes made here win unless the backend changed since it
///   was last seen and later than they were made (ties go to the backend,
///   as in the opening rule).
/// - Highlights made here that the backend doesn't have yet are added,
///   unless it has one with the very same range and words: an earlier add
///   got there but its answer didn't come back. BookOrbit returns a posted
///   CFI unchanged (measured against v3.6.0), so the strings match.
/// - Highlights removed here are removed from the backend, then forgotten.
public enum HighlightReconciliation {
    public struct Result: Equatable, Sendable {
        public var highlights: [LocalHighlight]
        /// Made here, still to add to the backend.
        public var toAdd: [LocalHighlight.ID]
        /// Changed here, still to send. Removals still to send are the
        /// highlights kept with `isRemoved`.
        public var toUpdate: [LocalHighlight.ID]
    }

    public static func reconcile(local: [LocalHighlight], remote: [SyncedHighlight]) -> Result {
        var unmatched = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var highlights: [LocalHighlight] = []
        var toAdd: [LocalHighlight.ID] = []
        var toUpdate: [LocalHighlight.ID] = []

        for var highlight in local {
            if let remoteID = highlight.remoteID {
                guard let synced = unmatched.removeValue(forKey: remoteID) else { continue }
                if !highlight.isRemoved {
                    highlight = merged(highlight, with: synced)
                    if !highlight.unsent.isEmpty { toUpdate.append(highlight.id) }
                }
                highlights.append(highlight)
            } else if !highlight.isRemoved {
                let landed = unmatched.values
                    .filter { $0.cfi != nil && $0.cfi == highlight.cfi && $0.text == highlight.text }
                    .min { $0.id < $1.id }
                if let landed {
                    unmatched[landed.id] = nil
                    highlight.remoteID = landed.id
                    highlight = merged(highlight, with: landed)
                    if !highlight.unsent.isEmpty { toUpdate.append(highlight.id) }
                } else if highlight.cfi != nil {
                    toAdd.append(highlight.id)
                }
                highlights.append(highlight)
            }
        }
        for synced in remote where unmatched[synced.id] != nil {
            highlights.append(LocalHighlight(
                cfi: synced.cfi, text: synced.text, color: synced.color ?? LocalHighlight.defaultColor, note: synced.note,
                createdAt: synced.createdAt ?? .now, remoteID: synced.id, syncedUpdatedAt: synced.updatedAt, chapter: synced.chapter
            ))
        }
        return Result(highlights: highlights, toAdd: toAdd, toUpdate: toUpdate)
    }

    /// `highlight` with the backend's copy taken in.
    static func merged(_ highlight: LocalHighlight, with synced: SyncedHighlight) -> LocalHighlight {
        var merged = highlight
        merged.cfi = synced.cfi
        merged.text = synced.text
        // A range that changed, or that this file no longer has, is placed
        // again, and named by the backend until then.
        if synced.cfi != highlight.cfi {
            merged.fraction = nil
            merged.chapter = synced.chapter
        } else {
            merged.chapter = merged.chapter ?? synced.chapter
        }

        let changedElsewhere = synced.updatedAt != highlight.syncedUpdatedAt
        let localWins: Bool = {
            guard !highlight.unsent.isEmpty else { return false }
            guard changedElsewhere, let theirs = synced.updatedAt else { return true }
            guard let ours = highlight.editedAt else { return false }
            return ours > theirs
        }()
        if localWins {
            if !highlight.unsent.contains(.color) { merged.color = synced.color ?? merged.color }
            if !highlight.unsent.contains(.note) { merged.note = synced.note }
        } else {
            merged.color = synced.color ?? merged.color
            merged.note = synced.note
            merged.unsent = []
            merged.editedAt = nil
        }
        merged.syncedUpdatedAt = synced.updatedAt
        return merged
    }
}

/// EPUB CFIs as text (#125).
public enum ReaderCFI {
    /// Where a range starts, as a point: `epubcfi(P,S,E)` is `epubcfi(PS)`.
    /// A point comes back as it is. A comma escaped with `^` isn't a
    /// separator.
    public static func start(of cfi: String) -> String {
        guard cfi.hasPrefix("epubcfi("), cfi.hasSuffix(")") else { return cfi }
        let body = cfi.dropFirst("epubcfi(".count).dropLast()
        var parts: [String] = [""]
        var escaped = false
        for character in body {
            if escaped {
                parts[parts.count - 1].append(character)
                escaped = false
            } else if character == "^" {
                parts[parts.count - 1].append(character)
                escaped = true
            } else if character == "," {
                parts.append("")
            } else {
                parts[parts.count - 1].append(character)
            }
        }
        guard parts.count == 3 else { return cfi }
        return "epubcfi(\(parts[0])\(parts[1]))"
    }

    /// Whether `a` starts before `b` in the book: their steps and character
    /// offsets compared in turn, ID assertions (`[…]`) and side biases left
    /// out. A step that's an ancestor of the other comes first.
    public static func starts(_ a: String, before b: String) -> Bool {
        let left = steps(start(of: a)), right = steps(start(of: b))
        for (x, y) in zip(left, right) where x != y { return x < y }
        return left.count < right.count
    }

    /// `epubcfi(/6/4!/4/38/2/1:143)` as `[6, 4, 4, 38, 2, 1, 143]`.
    static func steps(_ cfi: String) -> [Int] {
        var numbers: [Int] = []
        var current = ""
        var inAssertion = false
        for character in cfi {
            if inAssertion {
                if character == "]" { inAssertion = false }
                continue
            }
            if character == "[" {
                inAssertion = true
            } else if character.isASCII, character.isNumber {
                current.append(character)
                continue
            } else if character == "~" || character == "@" {
                // Temporal and spatial offsets don't order text.
                break
            }
            if let number = Int(current) { numbers.append(number) }
            current = ""
        }
        if let number = Int(current) { numbers.append(number) }
        return numbers
    }
}
