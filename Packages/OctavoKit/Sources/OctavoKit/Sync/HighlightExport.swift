import Foundation

/// A book's highlights as Markdown (#125), for Share All Highlights: the
/// title and author, then each chapter's quotes in the book's order with
/// their notes under them, and the ones this file doesn't have last. Every
/// quote and note is escaped, so nothing in a book or a note becomes a link,
/// a heading or markup.
public enum HighlightExport {
    public static func markdown(
        title: String, authors: [String], highlights: [LocalHighlight], notFound: [LocalHighlight], notFoundHeading: String
    ) -> String {
        var lines: [String] = []
        lines.append("# " + escaped(title.isEmpty ? "Highlights" : title))
        if !authors.isEmpty { lines.append(""); lines.append(escaped(authors.joined(separator: ", "))) }
        var chapter: String?? = .none
        for highlight in highlights {
            if chapter != .some(highlight.chapter) {
                chapter = .some(highlight.chapter)
                if let heading = highlight.chapter, !heading.isEmpty {
                    lines.append("")
                    lines.append("## " + escaped(heading))
                }
            }
            lines.append(contentsOf: entry(highlight))
        }
        if !notFound.isEmpty {
            lines.append("")
            lines.append("## " + escaped(notFoundHeading))
            for highlight in notFound { lines.append(contentsOf: entry(highlight)) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The file's name: "<Title> – Highlights.md", with nothing a file name
    /// can't hold.
    public static func fileName(title: String, suffix: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
        let cleaned = title.unicodeScalars.map { unsafe.contains($0) ? "-" : String($0) }.joined()
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        let base = cleaned.isEmpty ? suffix : "\(String(cleaned.prefix(100))) – \(suffix)"
        return base + ".md"
    }

    private static func entry(_ highlight: LocalHighlight) -> [String] {
        var lines = [""]
        lines += highlight.text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + escaped(String($0)) }
        if let note = highlight.note, !note.isEmpty {
            lines.append("")
            lines += note.split(separator: "\n", omittingEmptySubsequences: false).map { escaped(String($0)) }
        }
        return lines
    }

    /// Markdown's own characters taken literally: those that make emphasis,
    /// links, code or HTML anywhere, and those that start a heading, a list,
    /// a quote or a table at the start of a line. The rest, "Mr." included,
    /// stays as it is, as the text is shared as it is too.
    static func escaped(_ text: String) -> String {
        var out = ""
        for character in text {
            if "\\`*_[]<>".contains(character) { out.append("\\") }
            out.append(character)
        }
        let trimmed = out.drop { $0 == " " }
        let indent = String(out.prefix(out.count - trimmed.count))
        if let first = trimmed.first, "#+-|=>".contains(first) {
            return indent + "\\" + trimmed
        }
        // "1." or "1)" would start a numbered list.
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, let after = trimmed.dropFirst(digits.count).first, after == "." || after == ")" {
            return indent + digits + "\\" + trimmed.dropFirst(digits.count)
        }
        return out
    }
}
