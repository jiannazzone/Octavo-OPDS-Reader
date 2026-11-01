import Foundation

/// Reads an OPDS 2.0 feed (or a single publication) with `Codable`.
///
/// Lenient the way the Readium Web Publication Manifest allows: titles may
/// be language maps, contributors strings or objects (one or many), `rel`
/// a string or an array. Items that don't decode are dropped, not fatal.
enum OPDSJSONParser {
    static func parse(_ data: Data, url: URL) throws -> OPDSFeed {
        guard let document = try? JSONDecoder().decode(Document.self, from: data) else { throw LibraryError.invalidResponse }
        if let publication = document.singlePublication {
            // An `application/opds-publication+json` document.
            return OPDSFeed(title: publication.metadata.title, publications: [publication.publication(base: url)])
        }
        guard document.isFeed else { throw LibraryError.invalidResponse }
        return OPDSFeed(
            identifier: document.metadata?.identifier,
            title: document.metadata?.title,
            links: document.links.map { $0.link(base: url) },
            navigation: document.navigation.map { $0.navigation(base: url) },
            publications: document.publications.map { $0.publication(base: url) },
            groups: document.groups.map { group in
                OPDSGroup(
                    title: group.metadata?.title ?? "",
                    links: group.links.map { $0.link(base: url) },
                    navigation: group.navigation.map { $0.navigation(base: url) },
                    publications: group.publications.map { $0.publication(base: url) },
                    numberOfItems: group.metadata?.numberOfItems
                )
            },
            totalResults: document.metadata?.numberOfItems
        )
    }

    // MARK: - Wire format

    private struct Document: Decodable {
        var metadata: FeedMetadata?
        var links: [Link]
        var navigation: [Link]
        var publications: [Publication]
        var groups: [Group]
        /// Set when the document is one publication rather than a feed.
        var singlePublication: Publication?
        var isFeed: Bool

        enum CodingKeys: String, CodingKey { case metadata, links, navigation, publications, groups }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            links = c.lenient(LossyArray<Link>.self, .links)?.elements ?? []
            navigation = c.lenient(LossyArray<Link>.self, .navigation)?.elements ?? []
            publications = c.lenient(LossyArray<Publication>.self, .publications)?.elements ?? []
            groups = c.lenient(LossyArray<Group>.self, .groups)?.elements ?? []
            isFeed = c.contains(.navigation) || c.contains(.publications) || c.contains(.groups)
            if !isFeed, let publication = try? Publication(from: decoder), !publication.metadata.title.isEmpty {
                singlePublication = publication
                metadata = nil
            } else {
                metadata = c.lenient(FeedMetadata.self, .metadata)
            }
        }
    }

    private struct FeedMetadata: Decodable {
        var title: String?
        var identifier: String?
        var numberOfItems: Int?

        enum CodingKeys: String, CodingKey { case title, identifier, numberOfItems }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = c.lenient(LocalizedString.self, .title)?.value
            identifier = c.lenient(String.self, .identifier)
            numberOfItems = c.lenient(Int.self, .numberOfItems)
        }
    }

    private struct Group: Decodable {
        var metadata: FeedMetadata?
        var links: [Link]
        var navigation: [Link]
        var publications: [Publication]

        enum CodingKeys: String, CodingKey { case metadata, links, navigation, publications }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            metadata = c.lenient(FeedMetadata.self, .metadata)
            links = c.lenient(LossyArray<Link>.self, .links)?.elements ?? []
            navigation = c.lenient(LossyArray<Link>.self, .navigation)?.elements ?? []
            publications = c.lenient(LossyArray<Publication>.self, .publications)?.elements ?? []
        }
    }

    private struct Link: Decodable {
        var href: String
        var type: String?
        var rels: [String]
        var title: String?
        var templated: Bool
        var numberOfItems: Int?
        var indirectTypes: [String]
        var width: Int?
        var height: Int?

        enum CodingKeys: String, CodingKey { case href, type, rel, title, templated, properties, width, height }
        enum PropertyKeys: String, CodingKey { case numberOfItems, indirectAcquisition }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            href = try c.decode(String.self, forKey: .href)
            type = c.lenient(String.self, .type)
            rels = c.lenient(OneOrMany<String>.self, .rel)?.values ?? []
            title = c.lenient(String.self, .title)
            templated = c.lenient(Bool.self, .templated) ?? false
            width = c.lenient(Int.self, .width)
            height = c.lenient(Int.self, .height)
            let properties = try? c.nestedContainer(keyedBy: PropertyKeys.self, forKey: .properties)
            numberOfItems = properties?.lenient(Int.self, .numberOfItems)
            var types: [String] = []
            var level = properties?.lenient(LossyArray<Indirect>.self, .indirectAcquisition)?.elements.first
            while let indirect = level {
                types.append(indirect.type)
                level = indirect.child.first
            }
            indirectTypes = types
        }

        func link(base: URL) -> OPDSLink {
            OPDSLink(
                href: href, base: base, rels: rels, type: type, title: title,
                count: numberOfItems, templated: templated, indirectTypes: indirectTypes,
                width: width, height: height
            )
        }

        func navigation(base: URL) -> OPDSNavigation {
            OPDSNavigation(title: title ?? "", link: link(base: base))
        }
    }

    private struct Indirect: Decodable {
        var type: String
        var child: [Indirect]

        enum CodingKeys: String, CodingKey { case type, child }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            child = c.lenient(LossyArray<Indirect>.self, .child)?.elements ?? []
        }
    }

    private struct Publication: Decodable {
        var metadata: PublicationMetadata
        var links: [Link]
        var images: [Link]

        enum CodingKeys: String, CodingKey { case metadata, links, images }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            metadata = try c.decode(PublicationMetadata.self, forKey: .metadata)
            links = c.lenient(LossyArray<Link>.self, .links)?.elements ?? []
            images = c.lenient(LossyArray<Link>.self, .images)?.elements ?? []
        }

        func publication(base: URL) -> OPDSPublication {
            OPDSPublication(
                identifier: metadata.identifier,
                title: metadata.title,
                subtitle: metadata.subtitle,
                authors: metadata.authors.map { $0.contributor(base: base) },
                summary: metadata.description,
                publisher: metadata.publishers.first?.name,
                language: metadata.languages.first,
                published: metadata.published,
                series: metadata.series.map { series in
                    OPDSSeries(name: series.name, position: series.position, link: series.links.first?.link(base: base))
                },
                links: links.map { $0.link(base: base) },
                images: images.map { $0.link(base: base) }
            )
        }
    }

    private struct PublicationMetadata: Decodable {
        var identifier: String?
        var title: String
        var subtitle: String?
        var authors: [Contributor]
        var publishers: [Contributor]
        var languages: [String]
        var published: String?
        var description: String?
        var series: [Contributor]

        enum CodingKeys: String, CodingKey {
            case identifier, title, subtitle, author, contributor, publisher, language, published, description, belongsTo
        }
        enum BelongsToKeys: String, CodingKey { case series }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            identifier = c.lenient(String.self, .identifier)
            title = c.lenient(LocalizedString.self, .title)?.value ?? ""
            subtitle = c.lenient(LocalizedString.self, .subtitle)?.value
            // Komga lists its authors as plain `contributor`s.
            authors = c.lenient(Contributors.self, .author)?.values ?? c.lenient(Contributors.self, .contributor)?.values ?? []
            publishers = c.lenient(Contributors.self, .publisher)?.values ?? []
            languages = c.lenient(OneOrMany<String>.self, .language)?.values ?? []
            published = c.lenient(String.self, .published)
            description = c.lenient(String.self, .description)
            let belongsTo = try? c.nestedContainer(keyedBy: BelongsToKeys.self, forKey: .belongsTo)
            series = belongsTo?.lenient(Contributors.self, .series)?.values ?? []
        }
    }

    /// A contributor or a series: a name, or an object with one.
    private struct Contributor: Decodable {
        var name: String
        var sortAs: String?
        var position: Double?
        var links: [Link]

        enum CodingKeys: String, CodingKey { case name, sortAs, position, links }

        init(from decoder: any Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                self.name = name
                links = []
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let name = c.lenient(LocalizedString.self, .name)?.value, !name.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "No name")
            }
            self.name = name
            sortAs = c.lenient(String.self, .sortAs)
            position = c.seriesIndex(.position)
            links = c.lenient(LossyArray<Link>.self, .links)?.elements ?? []
        }

        func contributor(base: URL) -> OPDSContributor {
            OPDSContributor(name: name, sortAs: sortAs, link: links.first?.link(base: base))
        }
    }

    private struct Contributors: Decodable {
        var values: [Contributor]

        init(from decoder: any Decoder) throws {
            if let many = try? LossyArray<Contributor>(from: decoder) {
                values = many.elements
            } else {
                values = [try Contributor(from: decoder)]
            }
        }
    }

    private struct OneOrMany<Value: Decodable>: Decodable {
        var values: [Value]

        init(from decoder: any Decoder) throws {
            if let one = try? decoder.singleValueContainer().decode(Value.self) {
                values = [one]
            } else {
                values = try LossyArray<Value>(from: decoder).elements
            }
        }
    }

    /// A string, or a map of language codes to strings.
    private struct LocalizedString: Decodable {
        var value: String

        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let string = try? c.decode(String.self) {
                value = string
            } else {
                let map = try c.decode([String: String].self)
                let preferred = Locale.preferredLanguages.lazy.compactMap { map[$0] ?? map[String($0.prefix(2))] }.first
                value = preferred ?? map["en"] ?? map.sorted { $0.key < $1.key }.first?.value ?? ""
            }
        }
    }
}
