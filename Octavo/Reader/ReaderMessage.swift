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
    /// The user tapped the middle of the page.
    case tap(zone: String)
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
    }

    nonisolated struct Relocation: Codable, Equatable, Sendable {
        /// foliate's synthetic "location" counter. Either side can be `nil`
        /// while a section is still being measured.
        nonisolated struct Location: Codable, Equatable, Sendable {
            var current: Int?
            var total: Int?
        }

        var cfi: String?
        /// Progress through the whole book. foliate reports 0...1; `nil` if it
        /// couldn't compute one (JSON has no NaN).
        var fraction: Double?
        var tocLabel: String?
        var sectionIndex: Int?
        var sectionCount: Int?
        var location: Location?

        /// The position to persist and sync.
        var position: ReadingPosition {
            ReadingPosition(cfi: cfi, fraction: min(max(fraction ?? 0, 0), 1))
        }
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
        case type, zone, level, message
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
