import Foundation

/// A catalog's search: a URL template with the query left open.
///
/// OPDS 1.2 servers link an OpenSearch description (`{searchTerms}`), and
/// some link the template straight away (Calibre-Web). OPDS 2 links an
/// RFC 6570 template (`{?query}`).
struct OPDSSearchTemplate: Hashable, Sendable {
    var template: String
    var base: URL

    /// The search URL for `query`. Unknown parameters are left empty, as
    /// OpenSearch allows for optional ones.
    func url(for query: String) -> URL? {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            result += expand(rest[rest.index(after: open)..<close], query: query)
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return URL(string: result, relativeTo: base)?.absoluteURL
    }

    private func expand(_ expression: Substring, query: String) -> String {
        var expression = expression
        // RFC 6570 operators used by OPDS 2 servers.
        let op = expression.first.flatMap { "?&+#".contains($0) ? $0 : nil }
        if op != nil { expression = expression.dropFirst() }
        let names = expression.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "?*")) }
        let pairs = names.compactMap { name -> (String, String)? in
            // OpenSearch's prefixed names, like `opensearch:searchTerms`.
            let local = name.split(separator: ":").last.map(String.init) ?? name
            return ["searchTerms", "query", "q", "term", "keywords"].contains(local) ? (name, Self.encode(query)) : nil
        }
        switch op {
        case "?", "&":
            guard !pairs.isEmpty else { return "" }
            return String(op!) + pairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        default:
            return pairs.first?.1 ?? ""
        }
    }

    /// Percent-encodes everything but RFC 3986's unreserved characters, so
    /// the query is safe in a path segment and in a query.
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? value
    }
}

/// Reads an OpenSearch description document for its search template,
/// preferring the URL that returns an OPDS feed.
enum OpenSearchDescriptionParser {
    static func template(in data: Data, url: URL) -> OPDSSearchTemplate? {
        let handler = Handler()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        guard parser.parse() else { return nil }
        let ranked = handler.urls.sorted { rank($0.type) < rank($1.type) }
        return ranked.first.map { OPDSSearchTemplate(template: $0.template, base: url) }
    }

    private static func rank(_ type: String?) -> Int {
        let type = type?.lowercased() ?? ""
        if type.contains("opds-catalog") || type.contains("opds+json") { return 0 }
        if type.contains("atom+xml") { return 1 }
        return 2
    }

    private final class Handler: NSObject, XMLParserDelegate {
        var urls: [(template: String, type: String?)] = []

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            guard name == "Url", let template = attributes["template"], !template.isEmpty else { return }
            let type = attributes["type"]
            // HTML results aren't a feed we can read.
            if type?.lowercased().hasPrefix("text/html") == true { return }
            urls.append((template, type))
        }
    }
}
