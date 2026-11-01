import Foundation

/// Reads an OPDS 1.2 (Atom) feed, or a single Atom entry, with `XMLParser`.
///
/// Lenient where servers differ: a missing default namespace counts as Atom,
/// an entry is a book if it has an acquisition link (or cover art and no
/// feed link), and anything unknown is skipped. External entities are never
/// resolved.
enum OPDSAtomParser {
    static func parse(_ data: Data, url: URL) throws -> OPDSFeed {
        let handler = AtomHandler(base: url)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = handler
        guard parser.parse(), handler.sawRoot else { throw LibraryError.invalidResponse }
        return handler.feed
    }
}

private enum Namespace {
    static let atom = "http://www.w3.org/2005/Atom"
    static let dcTerms = "http://purl.org/dc/terms/"
    static let dcElements = "http://purl.org/dc/elements/1.1/"
    static let openSearch = "http://a9.com/-/spec/opensearch/1.1/"
    static let opds = "http://opds-spec.org/2010/catalog"
}

private final class AtomHandler: NSObject, XMLParserDelegate {
    private struct Entry {
        var identifier: String?
        var title: String?
        var authors: [OPDSContributor] = []
        var content: String?
        var summary: String?
        var publisher: String?
        var language: String?
        var issued: String?
        var published: String?
        var links: [OPDSLink] = []
    }

    let base: URL
    var feed = OPDSFeed()
    private(set) var sawRoot = false

    private var depth = 0
    private var entry: Entry?
    private var entryDepth = 0
    private var link: OPDSLink?
    private var author: (name: String?, uri: String?)?
    private var text = ""
    /// Inside `<content type="xhtml">`: its markup, written back out as HTML.
    private var xhtml: (field: String, depth: Int, markup: String)?

    init(base: URL) {
        self.base = base
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        depth += 1
        if var xhtml {
            xhtml.depth += 1
            xhtml.markup += "<\(name)" + attributes.map { " \($0.key)=\"\(escape($0.value))\"" }.joined() + ">"
            self.xhtml = xhtml
            return
        }
        text = ""
        let ns = namespaceURI ?? ""
        if ns == Namespace.atom || ns.isEmpty {
            switch name {
            case "feed" where depth == 1:
                sawRoot = true
            case "entry" where entry == nil:
                if depth == 1 { sawRoot = true }
                entry = Entry()
                entryDepth = depth
            case "link":
                link = makeLink(attributes)
            case "author" where entry != nil:
                author = (nil, nil)
            case "content", "summary":
                if entry != nil, attributes["type"]?.lowercased() == "xhtml" {
                    xhtml = (name, 0, "")
                }
            default:
                break
            }
        } else if ns == Namespace.opds, name == "indirectAcquisition", let type = attributes["type"] {
            link?.indirectTypes.append(type)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if xhtml != nil {
            xhtml?.markup += escape(string)
        } else {
            text += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        self.parser(parser, foundCharacters: String(decoding: block, as: UTF8.self))
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { depth -= 1 }
        if let current = xhtml {
            if current.depth > 0 {
                xhtml?.depth -= 1
                xhtml?.markup += "</\(name)>"
                return
            }
            xhtml = nil
            set(name, to: current.markup)
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        let ns = namespaceURI ?? ""
        switch ns {
        case Namespace.atom, "":
            endAtom(name, value)
        case Namespace.dcTerms, Namespace.dcElements:
            switch name {
            case "language": entry?.language = value.nilIfEmpty
            case "publisher": entry?.publisher = value.nilIfEmpty
            case "issued", "date": entry?.issued = value.nilIfEmpty
            default: break
            }
        case Namespace.openSearch where name == "totalResults":
            feed.totalResults = Int(value)
        default:
            break
        }
    }

    private func endAtom(_ name: String, _ value: String) {
        switch name {
        case "title":
            if entry != nil {
                if depth == entryDepth + 1 { entry?.title = value }
            } else if depth == 2 {
                feed.title = value.nilIfEmpty
            }
        case "id":
            if entry != nil {
                if depth == entryDepth + 1 { entry?.identifier = value.nilIfEmpty }
            } else if depth == 2 {
                feed.identifier = value.nilIfEmpty
            }
        case "name" where author != nil:
            author?.name = value
        case "uri" where author != nil:
            author?.uri = value
        case "author":
            if let author, let name = author.name?.nilIfEmpty {
                entry?.authors.append(OPDSContributor(
                    name: name,
                    link: author.uri?.nilIfEmpty.map { OPDSLink(href: $0, base: base) }
                ))
            }
            author = nil
        case "link":
            if let link {
                if entry != nil { entry?.links.append(link) } else { feed.links.append(link) }
            }
            link = nil
        case "content", "summary":
            set(name, to: value)
        case "published":
            entry?.published = value.nilIfEmpty
        case "entry" where depth == entryDepth:
            if let entry { add(entry) }
            entry = nil
        default:
            break
        }
    }

    private func set(_ field: String, to value: String) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if field == "content" { entry?.content = value } else { entry?.summary = value }
    }

    private func makeLink(_ attributes: [String: String]) -> OPDSLink? {
        guard let href = attributes["href"]?.trimmingCharacters(in: .whitespaces), !href.isEmpty else { return nil }
        return OPDSLink(
            href: href,
            base: base,
            rels: (attributes["rel"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init),
            type: attributes["type"],
            title: attributes["title"],
            length: attribute("length", in: attributes).flatMap { Int($0) },
            count: attribute("count", in: attributes).flatMap { Int($0) }
        )
    }

    /// By local name: `thr:count` arrives as `count` or `thr:count`
    /// depending on the parser.
    private func attribute(_ local: String, in attributes: [String: String]) -> String? {
        attributes[local] ?? attributes.first { $0.key.hasSuffix(":" + local) }?.value
    }

    private func add(_ entry: Entry) {
        let title = entry.title ?? ""
        let catalogLink = entry.links.first { $0.has(rel: "subsection") && $0.isCatalog }
            ?? entry.links.first { link in
                link.isCatalog && !link.isAcquisition && !(link.type ?? "").contains("type=entry")
                    && !["related", "up", "start", "self", "search"].contains { link.has(rel: $0) }
            }
        let hasAcquisition = entry.links.contains(where: \.isAcquisition)
        let images = entry.links.filter { $0.has(rel: OPDSRel.image) || $0.has(rel: OPDSRel.thumbnail) || $0.has(rel: OPDSRel.stanzaImage) || $0.has(rel: OPDSRel.stanzaThumbnail) }

        if !hasAcquisition, let catalogLink {
            feed.navigation.append(OPDSNavigation(
                identifier: entry.identifier,
                title: title,
                summary: entry.summary ?? entry.content,
                link: catalogLink,
                images: images,
                authors: entry.authors
            ))
        } else if hasAcquisition || !images.isEmpty {
            feed.publications.append(OPDSPublication(
                identifier: entry.identifier,
                title: title,
                authors: entry.authors,
                summary: entry.content ?? entry.summary,
                publisher: entry.publisher,
                language: entry.language,
                published: entry.issued ?? entry.published,
                links: entry.links
            ))
        }
    }

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
