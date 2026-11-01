import Foundation

// Made-up catalogs for the OPDS tests, written for Octavo. They copy the
// shapes the four dev servers send (dev/opds/README.md), not their text.

enum OPDSFixtures {
    /// A navigation root: an entry with no rel (Calibre-Web), one with a
    /// count and an icon (COPS), one with XHTML content and a relative link.
    static let atomRoot = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:thr="http://purl.org/syndication/thread/1.0">
      <id>urn:octavo:test:root</id>
      <title>Harbour Library</title>
      <link rel="self" href="/catalog" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
      <link rel="search" href="/catalog/opensearch.xml" type="application/opensearchdescription+xml"/>
      <link rel="http://opds-spec.org/sort/new" href="/catalog/newest" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      <entry>
        <title>Shelf picks</title>
        <id>picks</id>
        <content type="text">Hand-picked by the harbour master</content>
        <link href="/catalog/picks" type="application/atom+xml;profile=opds-catalog"/>
      </entry>
      <entry>
        <title>Everything</title>
        <id>allbooks</id>
        <link rel="subsection" href="/catalog/all" type="application/atom+xml;profile=opds-catalog;kind=acquisition" thr:count="42"/>
        <link rel="http://opds-spec.org/image/thumbnail" href="/icons/all.png" type="image/png" title="icon"/>
      </entry>
      <entry>
        <title>Writers</title>
        <id>writers</id>
        <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml">By <b>name</b></div></content>
        <link rel="subsection" href="catalog/writers" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
      </entry>
    </feed>
    """

    /// One page of books: formats in a muddled order, a purchase, a DRM
    /// loan, mislabelled Kindle and FB2 types, and a next page.
    static let atomBooks = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:opds="http://opds-spec.org/2010/catalog" xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
      <id>urn:octavo:test:all</id>
      <title>Everything</title>
      <opensearch:totalResults>3</opensearch:totalResults>
      <link rel="self" href="/catalog/all" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      <link rel="next" href="/catalog/all?page=2" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
      <entry>
        <title>The Lighthouse Keeper&apos;s Almanac</title>
        <id>urn:uuid:11111111-1111-4111-8111-111111111111</id>
        <author><name>Mara Quill</name><uri>/catalog/authors/7</uri></author>
        <author><name>Tobias Fenn</name><uri>https://example.org/tobias</uri></author>
        <dcterms:language>en</dcterms:language>
        <dcterms:publisher>Tidewater Press</dcterms:publisher>
        <published>1911-04-02T08:00:00Z</published>
        <content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>A year of <i>weather</i> &amp; lamps.</p></div></content>
        <link rel="http://opds-spec.org/image" href="/covers/1.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/image/thumbnail" href="/covers/1-small.jpg" type="image/jpeg"/>
        <link rel="http://opds-spec.org/acquisition" href="/get/1.pdf" type="application/pdf" length="900"/>
        <link rel="http://opds-spec.org/acquisition" href="/get/1/mobi/" type="application/x-mobipocket-ebook" title="MOBI" length="300"/>
        <link rel="http://opds-spec.org/acquisition" href="/get/1/azw3/" type="application/x-mobipocket-ebook" title="AZW3" length="310"/>
        <link rel="http://opds-spec.org/acquisition/open-access" href="/get/1.epub" type="application/epub+zip" length="200"/>
        <link rel="http://opds-spec.org/acquisition/buy" href="/buy/1" type="text/html"/>
        <link rel="http://opds-spec.org/acquisition" href="/loan/1" type="application/vnd.adobe.adept+xml">
          <opds:indirectAcquisition type="application/epub+zip"/>
        </link>
        <link rel="related" href="/catalog/authors/7" type="application/atom+xml;profile=opds-catalog" title="More by Mara Quill"/>
      </entry>
      <entry>
        <title>Salt Roads</title>
        <id>urn:uuid:22222222-2222-4222-8222-222222222222</id>
        <author><name>Ines Calder</name></author>
        <summary type="text">Short summary only.</summary>
        <link rel="http://opds-spec.org/acquisition" href="/get/2/fb2/" type="application/fb2+zip" title="FB2"/>
        <link rel="http://opds-spec.org/acquisition" href="/get/2.fb2.zip" type="application/x-zip-compressed-fb2"/>
        <link rel="http://opds-spec.org/acquisition" href="/get/2.azw3" type="application/x-mobi8-ebook"/>
      </entry>
    </feed>
    """

    /// A root that lists books and nothing else.
    static let atomBooksOnlyRoot = """
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Pocket Shelf</title>
      <entry>
        <title>Salt Roads</title>
        <id>urn:uuid:22222222-2222-4222-8222-222222222222</id>
        <link rel="http://opds-spec.org/acquisition" href="/get/2.epub" type="application/epub+zip"/>
      </entry>
    </feed>
    """

    /// Calibre-Web's way: no sort/new link, a template right in the root.
    static let atomRootCalibreWebStyle = """
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Calibre-Web</title>
      <link rel="search" href="/opds/osd" type="application/opensearchdescription+xml"/>
      <link type="application/atom+xml" rel="search" title="Search" href="/opds/search/{searchTerms}"/>
      <entry><title>Hot Books</title><id>/opds/hot</id><link href="/opds/hot" type="application/atom+xml;profile=opds-catalog"/></entry>
      <entry><title>Alphabetical Books</title><id>/opds/books</id><link href="/opds/books" type="application/atom+xml;profile=opds-catalog"/></entry>
      <entry><title>Recently added Books</title><id>/opds/new</id><link href="/opds/new" type="application/atom+xml;profile=opds-catalog"/></entry>
    </feed>
    """

    /// Kavita's way: ids name the lists, and the key is in every path.
    static let atomRootKavitaStyle = """
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Kavita</title>
      <entry><id>onDeck</id><title>On Deck</title><link rel="subsection" type="application/atom+xml;profile=opds-catalog;kind=navigation" href="/api/opds/KEY/on-deck"/></entry>
      <entry><id>recentlyAdded</id><title>Recently Added</title><link rel="subsection" type="application/atom+xml;profile=opds-catalog;kind=navigation" href="/api/opds/KEY/recently-added"/></entry>
      <entry><id>allLibraries</id><title>All Libraries</title><link rel="subsection" type="application/atom+xml;profile=opds-catalog;kind=navigation" href="/api/opds/KEY/libraries"/></entry>
    </feed>
    """

    static let openSearchDescription = """
    <?xml version="1.0" encoding="UTF-8"?>
    <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
      <ShortName>Harbour</ShortName>
      <Url type="text/html" template="/web/search?q={searchTerms}"/>
      <Url type="application/atom+xml;profile=opds-catalog;kind=acquisition" template="/catalog/search?q={searchTerms}&amp;page={startPage?}"/>
    </OpenSearchDescription>
    """

    /// A single full entry (an `alternate` link's target).
    static let atomEntry = """
    <entry xmlns="http://www.w3.org/2005/Atom">
      <title>Salt Roads</title>
      <id>urn:uuid:22222222-2222-4222-8222-222222222222</id>
      <author><name>Ines Calder</name></author>
      <content type="html">&lt;p&gt;The long version.&lt;/p&gt;</content>
      <link rel="http://opds-spec.org/acquisition" href="/get/2.epub" type="application/epub+zip"/>
    </entry>
    """

    /// OPDS 2: navigation, a group with its own list, a group without one,
    /// language maps, contributors in three shapes, sized images, and a
    /// publication that doesn't decode.
    static let json = """
    {
      "metadata": {"title": "Harbour Library", "numberOfItems": 7},
      "links": [
        {"rel": "self", "href": "/v2/home", "type": "application/opds+json"},
        {"rel": "search", "href": "/v2/search{?query}", "type": "application/opds+json", "templated": true},
        {"rel": ["next"], "href": "/v2/home?page=2", "type": "application/opds+json"}
      ],
      "navigation": [
        {"title": "Home", "href": "/v2/home", "type": "application/opds+json", "rel": "current"},
        {"title": "Browse", "href": "/v2/browse", "type": "application/opds+json", "properties": {"numberOfItems": 12}}
      ],
      "groups": [
        {
          "metadata": {"title": "Latest Books", "numberOfItems": 2},
          "links": [{"rel": "self", "href": "/v2/latest", "type": "application/opds+json"}],
          "publications": [\(tideTables)]
        },
        {
          "metadata": {"title": "Shelves"},
          "navigation": [{"title": "Winter reads", "href": "/v2/shelves/1", "type": "application/opds+json"}]
        }
      ],
      "publications": [
        {
          "metadata": {"title": "Fog Signals", "contributor": "Ines Calder"},
          "links": [
            {"rel": "http://opds-spec.org/acquisition/borrow", "href": "/v2/books/b/loan", "type": "application/vnd.readium.lcp.license.v1.0+json"},
            {"rel": "http://opds-spec.org/acquisition", "href": "/v2/books/b/file", "type": "application/x-fictionbook+xml"}
          ],
          "images": [{"href": "/v2/books/b/cover"}]
        },
        {"links": []}
      ]
    }
    """

    /// A publication with a language map, a linked series and two image sizes.
    static let tideTables = """
    {
      "metadata": {
        "title": {"en": "Tide Tables", "la": "Tabulae"},
        "identifier": "urn:isbn:9780000000001",
        "author": [{"name": "Mara Quill", "sortAs": "Quill, Mara", "links": [{"href": "/v2/authors/7", "type": "application/opds+json"}]}],
        "belongsTo": {"series": {"name": "Coastal Almanacs", "position": "2", "links": [{"href": "/v2/series/3", "type": "application/opds+json"}]}},
        "language": ["en"],
        "published": "2020-01-15",
        "description": "<p>Charts.</p>"
      },
      "links": [{"rel": "http://opds-spec.org/acquisition", "href": "/v2/books/a/file", "type": "application/epub+zip"}],
      "images": [
        {"href": "/v2/books/a/small.jpg", "type": "image/jpeg", "width": 100, "height": 150},
        {"href": "/v2/books/a/large.jpg", "type": "image/jpeg", "width": 600, "height": 900}
      ]
    }
    """

    static let authenticationDocument = """
    {
      "id": "https://example.com/auth",
      "title": "Harbour",
      "description": "Use your harbour pass.",
      "authentication": [{"type": "http://opds-spec.org/auth/basic", "labels": {"login": "Email", "password": "Passphrase"}}]
    }
    """

    static let oauthOnlyDocument = """
    {"title": "Harbour", "authentication": [{"type": "http://opds-spec.org/auth/oauth/implicit"}]}
    """
}
