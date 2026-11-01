import Foundation
import OctavoKit

/// A message from the web reader (`ReaderWeb/bridge.js`).
///
/// The bridge posts every message as a JSON string shaped `{ type, ...payload }`.
/// Decoding is tolerant: unknown types become `.unknown`, and missing or `null`
/// optional fields stay `nil`, so a bridge change never crashes the app.
nonisolated enum ReaderMessage: Equatable, Sendable {
    /// `bridge.js` has loaded and `window.octavo` is callable.
    case ready
    /// A book finished opening and has been moved to its restored position.
    case opened(Opened)
    /// The visible page changed.
    case relocate(Relocation)
    /// The user tapped where the controls show: the `"middle"` of the page,
    /// or in book mode the side `"column"`; or anywhere while the controls
    /// cover the page (`"dismiss"`). See `ReaderTapMode`.
    case tap(zone: String)
    /// The page's size in CSS px (= points), sent on load and whenever it
    /// changes.
    case viewport(width: Double, height: Double)
    /// The user followed a link out of the book. The bridge has already
    /// stopped foliate from opening it.
    case externalLink(href: String)
    case error(ScriptError)
    /// A `console.error`/`console.warn` line from foliate-js.
    case log(level: String, message: String)
    case unknown(type: String)

    nonisolated struct Opened: Codable, Equatable, Sendable {
        /// Where the position came from: `"cfi"`, `"fraction"` or `"start"`.
        var restoredFrom: String
        var title: String?
        var sectionCount: Int
        var isFixedLayout: Bool
        /// The table of contents, flattened in reading order, each entry with
        /// where its section starts in the book. `nil` from an older bridge.
        var toc: [TOCEntry]?
    }

    nonisolated struct TOCEntry: Codable, Equatable, Sendable {
        var label: String
        /// Where the entry's section starts, 0...1 of the book.
        var fraction: Double?
    }

    nonisolated struct Relocation: Codable, Equatable, Sendable {
        /// foliate's synthetic "location" counter. Either side can be `nil`
        /// while a section is still being measured.
        nonisolated struct Location: Codable, Equatable, Sendable {
            /// The location the page starts in, from 0.
            var current: Int?
            /// The location the page ends in.
            var next: Int?
            var total: Int?
        }

        /// The visible page as a range CFI (stock foliate).
        var cfi: String?
        /// `cfi` collapsed to a point at the start of the page, the shape
        /// BookOrbit's web reader stores. `nil` from an older bridge.
        var startCFI: String?
        /// The page shows no content, so `cfi` names only the section (see
        /// `bridge.js` `isBlankPage`). Not worth saving or syncing.
        var blankPage: Bool?
        /// Progress through the whole book. foliate reports 0...1; `nil` if it
        /// couldn't compute one (JSON has no NaN).
        var fraction: Double?
        var tocLabel: String?
        var sectionIndex: Int?
        var sectionCount: Int?
        var location: Location?

        /// The position with the page's range CFI.
        var position: ReadingPosition { position(.range) }

        /// The position to persist and sync, with the CFI in `shape`. A point
        /// falls back to the range if the bridge didn't send one.
        func position(_ shape: CFIShape) -> ReadingPosition {
            let cfi = switch shape {
            case .range: cfi
            case .point: startCFI ?? cfi
            }
            return ReadingPosition(cfi: cfi, fraction: min(max(fraction ?? 0, 0), 1))
        }
    }

    /// Which CFI to keep for a page. Both open the same page in foliate.
    nonisolated enum CFIShape: String, CaseIterable, Sendable {
        /// The point where the page starts, as BookOrbit's web reader stores it.
        case point
        /// The range spanning the page, as stock foliate reports it.
        case range
    }

    nonisolated struct ScriptError: Codable, Equatable, Sendable {
        /// Where it happened: `"script"`, `"promise"`, or the bridge call's name.
        var phase: String?
        var message: String
        var name: String?
        var stack: String?
        var source: String?
        var line: Int?
    }

    nonisolated enum DecodingError: Error, Equatable {
        /// The script message body wasn't a string.
        case notAString
    }

    /// Decodes a `WKScriptMessage.body`.
    static func decode(_ body: Any) throws -> ReaderMessage {
        guard let string = body as? String else { throw DecodingError.notAString }
        return try JSONDecoder().decode(ReaderMessage.self, from: Data(string.utf8))
    }
}

nonisolated extension ReaderMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, zone, level, message, href, width, height
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "ready":
            self = .ready
        case "opened":
            self = .opened(try Opened(from: decoder))
        case "relocate":
            self = .relocate(try Relocation(from: decoder))
        case "tap":
            self = .tap(zone: try container.decodeIfPresent(String.self, forKey: .zone) ?? "middle")
        case "viewport":
            self = .viewport(
                width: try container.decode(Double.self, forKey: .width),
                height: try container.decode(Double.self, forKey: .height)
            )
        case "externalLink":
            self = .externalLink(href: try container.decode(String.self, forKey: .href))
        case "error":
            self = .error(try ScriptError(from: decoder))
        case "log":
            self = .log(
                level: try container.decodeIfPresent(String.self, forKey: .level) ?? "log",
                message: try container.decodeIfPresent(String.self, forKey: .message) ?? ""
            )
        default:
            self = .unknown(type: type)
        }
    }
}
