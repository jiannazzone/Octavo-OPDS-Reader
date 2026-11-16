import Foundation

/// BookOrbit's ten highlight colours (#125), in its web reader's order, and
/// how a stored colour is drawn. A colour is stored as the backend has it
/// and drawn as it is when it can be: a hex, or one of the ten by name.
/// Anything else is drawn in the default yellow, and never written back.
public enum HighlightPalette {
    public struct Color: Hashable, Sendable, Identifiable {
        /// BookOrbit's name for it, which other clients may store instead
        /// of the hex.
        public var name: String
        public var hex: String
        public var id: String { hex }
    }

    public static let colors: [Color] = [
        Color(name: "yellow", hex: "#FACC15"),
        Color(name: "green", hex: "#4ADE80"),
        Color(name: "blue", hex: "#38BDF8"),
        Color(name: "pink", hex: "#F472B6"),
        Color(name: "orange", hex: "#FB923C"),
        Color(name: "red", hex: "#F87171"),
        Color(name: "olive", hex: "#84CC16"),
        Color(name: "cyan", hex: "#22D3EE"),
        Color(name: "purple", hex: "#C084FC"),
        Color(name: "gray", hex: "#9CA3AF"),
    ]

    /// The one of the ten a stored colour is, if any: by hex in any case,
    /// or by name ("grey" too).
    public static func color(for stored: String) -> Color? {
        let trimmed = stored.trimmingCharacters(in: .whitespaces).lowercased()
        let name = trimmed == "grey" ? "gray" : trimmed
        return colors.first { $0.hex.lowercased() == trimmed || $0.name == name }
    }

    /// What the page draws for a stored colour: always `#` and 6 or 8 hex
    /// digits, so nothing else reaches the page's markup.
    public static func drawable(_ stored: String) -> String {
        if let known = color(for: stored) { return known.hex }
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return colors[0].hex }
        let digits = trimmed.dropFirst()
        guard digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return colors[0].hex }
        switch digits.count {
        case 6, 8: return "#" + digits.uppercased()
        // #RGB and #RGBA, each digit doubled.
        case 3, 4: return "#" + digits.map { "\($0)\($0)" }.joined().uppercased()
        default: return colors[0].hex
        }
    }
}
