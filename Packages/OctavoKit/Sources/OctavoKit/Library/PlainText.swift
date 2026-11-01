import Foundation

/// Plain text from the HTML a server or book supplies, such as a book's
/// description. The markup is the book's, so it's never rendered
/// (`docs/notes/formats-spike.md`): tags are dropped, the ends of blocks
/// become line breaks, entities are decoded and whitespace collapses as a
/// browser would collapse it. Show the result with `Text(verbatim:)` or a
/// `String`, never as Markdown or an attributed HTML string.
public enum PlainText {
    public static func fromHTML(_ html: String) -> String {
        guard containsMarkup(html) else {
            return decodingEntities(in: html.replacing("\r\n", with: "\n"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var pieces: [Piece] = []
        var text = ""
        var rest = html[...]
        while let open = rest.firstIndex(of: "<") {
            text += rest[..<open]
            rest = rest[open...]
            if rest.hasPrefix("<!--") {
                rest = rest.range(of: "-->").map { rest[$0.upperBound...] } ?? ""
                continue
            }
            guard let close = rest.firstIndex(of: ">") else { break }
            guard let tag = Tag(rest[rest.index(after: open)..<close]) else {
                // Not a tag, such as "a < b": keep the text.
                text += "<"
                rest = rest[rest.index(after: open)...]
                continue
            }
            rest = rest[rest.index(after: close)...]
            if tag.skipsContent, !tag.isClosing {
                rest = rest.range(of: "</\(tag.name)", options: .caseInsensitive).map { rest[$0.lowerBound...] } ?? ""
                continue
            }
            if let piece = tag.piece {
                pieces.append(.text(text))
                text = ""
                pieces.append(piece)
            }
        }
        text += rest
        pieces.append(.text(text))
        return assemble(pieces)
    }

    /// Whether `string` has anything that looks like a tag or a comment.
    static func containsMarkup(_ string: String) -> Bool {
        var rest = string[...]
        while let open = rest.firstIndex(of: "<") {
            rest = rest[rest.index(after: open)...]
            if let next = rest.first, next.isLetter || next == "/" || next == "!" { return true }
        }
        return false
    }

    private enum Piece {
        case text(String)
        case lineBreak
        case paragraphBreak
        case bullet
    }

    private struct Tag {
        var name: String
        var isClosing: Bool

        /// `nil` unless `inside` (between `<` and `>`) starts like a tag.
        init?(_ inside: Substring) {
            var body = inside.drop(while: \.isWhitespace)
            isClosing = body.first == "/"
            if isClosing { body = body.dropFirst() }
            guard let first = body.first, first.isLetter else { return nil }
            name = String(body.prefix { $0.isLetter || $0.isNumber }).lowercased()
        }

        /// Script and style text isn't content.
        var skipsContent: Bool { ["script", "style", "head", "title"].contains(name) }

        var piece: Piece? {
            switch name {
            case "br": .lineBreak
            case "li": isClosing ? .lineBreak : .bullet
            case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "ul", "ol",
                 "table", "section", "article", "header", "footer", "aside", "hr", "dl":
                .paragraphBreak
            case "tr", "dt", "dd", "figcaption": .lineBreak
            default: nil
            }
        }
    }

    /// Joins the pieces: each text run's whitespace collapses to single
    /// spaces, breaks merge (a paragraph break wins), and nothing leads or
    /// trails.
    private static func assemble(_ pieces: [Piece]) -> String {
        var output = ""
        var pendingBreak: String?
        var pendingBullet = false
        for piece in pieces {
            switch piece {
            case .text(let raw):
                let text = decodingEntities(in: collapsingWhitespace(raw))
                let trimmed = output.isEmpty || pendingBreak != nil || pendingBullet
                    ? text.trimmingCharacters(in: .whitespaces) : text
                guard !trimmed.trimmingCharacters(in: .whitespaces).isEmpty else {
                    if !trimmed.isEmpty, pendingBreak == nil, !pendingBullet, !output.isEmpty, output.last != " " { output += " " }
                    continue
                }
                if !output.isEmpty, let pendingBreak { output = output.trimmingTrailingSpaces() + pendingBreak }
                if pendingBullet { output += "• " }
                pendingBreak = nil
                pendingBullet = false
                output += trimmed
            case .lineBreak:
                if pendingBreak == nil { pendingBreak = "\n" }
            case .paragraphBreak:
                pendingBreak = "\n\n"
            case .bullet:
                if pendingBreak == nil { pendingBreak = "\n" }
                pendingBullet = true
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapsingWhitespace(_ string: String) -> String {
        var result = ""
        var lastWasSpace = false
        for character in string {
            if character.isWhitespace {
                if !lastWasSpace { result.append(" ") }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        return result
    }

    /// Decodes `&amp;`, `&#233;` and `&#xE9;`, plus the named entities that
    /// turn up in book descriptions. Anything else stays as written.
    static func decodingEntities(in string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var rest = string[...]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            rest = rest[amp...]
            let candidate = rest.dropFirst().prefix(12)
            if let semicolon = candidate.firstIndex(of: ";"),
               let decoded = entity(String(candidate[..<semicolon])) {
                result += decoded
                rest = rest[rest.index(after: semicolon)...]
            } else {
                result += "&"
                rest = rest.dropFirst()
            }
        }
        return result + rest
    }

    private static func entity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits, radix: 10)
            guard let value else { return nil }
            // NUL and anything that isn't a scalar (surrogates, past U+10FFFF).
            guard value != 0, let scalar = Unicode.Scalar(value) else { return "\u{FFFD}" }
            return String(Character(scalar))
        }
        return namedEntities[name]
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "times": "×", "shy": "",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "aacute": "á", "agrave": "à",
        "acirc": "â", "auml": "ä", "aring": "å", "ccedil": "ç", "iacute": "í", "icirc": "î",
        "iuml": "ï", "ntilde": "ñ", "oacute": "ó", "ocirc": "ô", "ouml": "ö", "oslash": "ø",
        "uacute": "ú", "ucirc": "û", "uuml": "ü", "szlig": "ß", "aelig": "æ", "oelig": "œ",
    ]
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var copy = self
        while copy.last == " " { copy.removeLast() }
        return copy
    }
}
