import Foundation

// One parsed OPDS document, whichever version it came in. The Atom (1.2) and
// JSON (2.0) parsers both produce these; `OPDSSource` maps them onto the
// library models. Only what a `LibrarySource` needs is kept: lending
// (holds, copies, prices) and facets are dropped.

/// A link as the document wrote it, with the document's URL to resolve it.
struct OPDSLink: Hashable, Sendable {
    /// As written: may be relative, or a template such as `/search/{searchTerms}`.
    var href: String
    /// The URL of the document the link came from.
    var base: URL
    var rels: [String] = []
    var type: String?
    var title: String?
    /// Bytes, for acquisition links.
    var length: Int?
    /// Items behind the link (`thr:count`, `properties.numberOfItems`).
    var count: Int?
    /// OPDS 2 URI template (`{?query}`); Atom templates are spotted by their braces.
    var templated = false
    /// For an indirect acquisition (`opds:indirectAcquisition`): the types
    /// inside the wrapper, outermost first.
    var indirectTypes: [String] = []
    /// OPDS 2 image sizes, for picking a thumbnail.
    var width: Int?
    var height: Int?

    /// The absolute URL, or `nil` for a template or a link that isn't one.
    var url: URL? {
        guard !isTemplate else { return nil }
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    var isTemplate: Bool { templated || href.contains("{") }

    /// `type` without parameters, lowercased: `application/atom+xml`.
    var mediaType: String? {
        type.map { $0.split(separator: ";").first.map(String.init) ?? $0 }?
            .trimmingCharacters(in: .whitespaces).lowercased()
    }

    func has(rel: String) -> Bool { rels.contains(rel) }

    /// A catalog feed (Atom or JSON), as opposed to a book file or an image.
    var isCatalog: Bool {
        guard let type = type?.lowercased() else { return false }
        return type.contains("atom+xml") || type.contains("opds+json") || type.contains("profile=opds-catalog")
    }

    var isAcquisition: Bool {
        rels.contains { $0.hasPrefix(OPDSRel.acquisition) }
    }
}

enum OPDSRel {
    static let acquisition = "http://opds-spec.org/acquisition"
    static let openAccess = "http://opds-spec.org/acquisition/open-access"
    static let image = "http://opds-spec.org/image"
    static let thumbnail = "http://opds-spec.org/image/thumbnail"
    static let sortNew = "http://opds-spec.org/sort/new"
    static let authDocument = "http://opds-spec.org/auth/document"
    // Stanza's names, still sent by some servers.
    static let stanzaImage = "x-stanza-cover-image"
    static let stanzaThumbnail = "x-stanza-cover-image-thumbnail"
}

struct OPDSContributor: Hashable, Sendable {
    var name: String
    var sortAs: String?
    /// Their books, when the server links them.
    var link: OPDSLink?
}

struct OPDSSeries: Hashable, Sendable {
    var name: String
    var position: Double?
    var link: OPDSLink?
}

/// A book entry.
struct OPDSPublication: Hashable, Sendable {
    var identifier: String?
    var title: String
    var subtitle: String?
    var authors: [OPDSContributor] = []
    /// Plain text or HTML.
    var summary: String?
    var publisher: String?
    var language: String?
    var published: String?
    var series: [OPDSSeries] = []
    /// Every link: acquisitions, images, the full entry, related feeds.
    var links: [OPDSLink] = []
    /// OPDS 2 `images`. Atom puts images among `links`.
    var images: [OPDSLink] = []

    var acquisitions: [OPDSLink] { links.filter(\.isAcquisition) }
}

/// An entry that leads to another feed.
struct OPDSNavigation: Hashable, Sendable {
    var identifier: String?
    var title: String
    var summary: String?
    var link: OPDSLink
    /// Cover art some servers give a list entry (Kavita's series).
    var images: [OPDSLink] = []
    var authors: [OPDSContributor] = []
}

/// An OPDS 2 group: a titled section with its own list behind `links`' self.
struct OPDSGroup: Hashable, Sendable {
    var title: String
    var links: [OPDSLink] = []
    var navigation: [OPDSNavigation] = []
    var publications: [OPDSPublication] = []
    var numberOfItems: Int?
}

struct OPDSFeed: Hashable, Sendable {
    var identifier: String?
    var title: String?
    var links: [OPDSLink] = []
    var navigation: [OPDSNavigation] = []
    var publications: [OPDSPublication] = []
    var groups: [OPDSGroup] = []
    /// Across all pages (`opensearch:totalResults`, `numberOfItems`).
    var totalResults: Int?

    func link(rel: String) -> OPDSLink? {
        links.first { $0.has(rel: rel) }
    }
}
