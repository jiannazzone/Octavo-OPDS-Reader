import Foundation

/// An FB2 book's cover, read from the file itself: the picture its
/// `<coverpage>` names, from the base64 `<binary>` with that ID. foliate
/// makes it a `data:` URL and fetches it, which the reader's CSP blocks
/// (`connect-src`), and the CSP stays as it is (Adam, 2026-11-01;
/// `docs/notes/formats-spike.md`).
///
/// Streams the XML, so a 70 MB illustrated FB2 isn't held in memory, keeps
/// only the cover's own characters, and never resolves external entities.
public enum FB2Cover {
    public struct Picture: Equatable, Sendable {
        public var data: Data
        /// As the file says: `"image/jpeg"`. `nil` if it doesn't.
        public var mimeType: String?
    }

    /// The cover of the FB2 at `url`, or `nil` without one (or one over
    /// `limit` bytes).
    public static func read(from url: URL, limit: Int = 16 << 20) -> Picture? {
        guard let stream = InputStream(url: url) else { return nil }
        return read(XMLParser(stream: stream), limit: limit)
    }

    public static func read(_ data: Data, limit: Int = 16 << 20) -> Picture? {
        read(XMLParser(data: data), limit: limit)
    }

    private static func read(_ parser: XMLParser, limit: Int) -> Picture? {
        let reader = Reader(limit: limit)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.parse()
        return reader.picture
    }

    private final class Reader: NSObject, XMLParserDelegate {
        let limit: Int
        var path: [String] = []
        /// The `<binary>` ID the cover page's first image names.
        var coverID: String?
        var collecting: (mimeType: String?, base64: [UInt8])?
        var picture: Picture?

        init(limit: Int) {
            self.limit = limit
        }

        /// The name without a namespace prefix: `l:href` is `href`.
        private func local(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            let element = local(name)
            path.append(element)
            if element == "image", coverID == nil, path.dropLast().contains("coverpage") {
                let href = attributes.first { local($0.key) == "href" }?.value ?? ""
                if href.hasPrefix("#"), href.count > 1 { coverID = String(href.dropFirst()) }
            } else if element == "binary", let coverID, attributes["id"] == coverID {
                collecting = (attributes["content-type"], [])
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard collecting != nil else { return }
            for byte in string.utf8 where !Self.isSpace(byte) {
                collecting?.base64.append(byte)
            }
            // Base64 is 4 characters for 3 bytes.
            if (collecting?.base64.count ?? 0) > limit / 3 * 4 + 4 {
                collecting = nil
                parser.abortParsing()
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            path.removeLast()
            guard local(name) == "binary", let collected = collecting else { return }
            collecting = nil
            if let data = Data(base64Encoded: Data(collected.base64)), !data.isEmpty {
                picture = Picture(data: data, mimeType: collected.mimeType)
            }
            parser.abortParsing()
        }

        private static func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
        }
    }
}
