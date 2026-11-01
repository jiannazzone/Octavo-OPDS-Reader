import Foundation
@testable import OctavoKit
import Testing

/// Response shapes as BookOrbit v3.6.0 sends them, trimmed.
struct BookOrbitDecodingTests {
    let decoder = BookOrbitClient.makeDecoder()

    @Test func decodesListBookWithAuthorNamesAndIgnoresUnknownFields() throws {
        let json = #"""
        {"id":4,"libraryId":1,"status":"present","title":"Pride and Prejudice","seriesId":null,
         "authors":["Jane Austen"],"files":[{"id":4,"format":"epub","role":"primary","sizeBytes":24873112,
         "mediaOverlay":{"available":false}}],"readingProgress":12.5,"hasCover":true,
         "coverVersion":"ebook:2026-10-31T15:44:06.311Z:-","somethingNew":{"nested":[1,2,3]}}
        """#
        let book = try decoder.decode(BookOrbitBook.self, from: Data(json.utf8))
        #expect(book.id == 4)
        #expect(book.libraryID == 1)
        #expect(book.authors == ["Jane Austen"])
        #expect(book.files == [BookOrbitFile(id: 4, format: "epub", role: "primary", sizeBytes: 24_873_112, filename: nil)])
        #expect(book.primaryFile?.id == 4)
        #expect(book.readingFraction == 0.125)
        #expect(book.hasCover == true)
    }

    @Test func decodesDetailBookWithAuthorObjects() throws {
        let json = #"""
        {"id":1,"title":"Alice's Adventures in Wonderland","authors":[{"id":1,"name":"Lewis Carroll","sortName":"Carroll, Lewis"}],
         "description":"<p>A girl falls down a rabbit hole.</p>","language":"en","publisher":null,
         "files":[{"id":9,"format":"pdf","role":"alternate"},{"id":1,"format":"epub","role":"primary",
         "filename":"Alice's Adventures in Wonderland (2008).epub","sizeBytes":189249}]}
        """#
        let book = try decoder.decode(BookOrbitBook.self, from: Data(json.utf8))
        #expect(book.authors == ["Lewis Carroll"])
        #expect(book.language == "en")
        #expect(book.publisher == nil)
        #expect(book.primaryFile?.id == 1)
        #expect(book.primaryFile?.filename == "Alice's Adventures in Wonderland (2008).epub")
        #expect(book.readingFraction == nil)
    }

    @Test func toleratesMissingAndMistypedOptionalFields() throws {
        let json = #"{"id":7,"title":"Untitled","seriesIndex":"two","files":null}"#
        let book = try decoder.decode(BookOrbitBook.self, from: Data(json.utf8))
        #expect(book.authors.isEmpty)
        #expect(book.files.isEmpty)
        #expect(book.seriesIndex == nil)
        #expect(book.primaryFile == nil)
    }

    /// v3.6 sends `seriesIndex` as a string; older servers as a number.
    @Test(arguments: [
        (#""2""#, 2.0), (#""2.5""#, 2.5), ("3", 3.0), ("1.5", 1.5), (#"" 4 ""#, 4.0),
        (#""two""#, nil), (#""nan""#, nil), (#""inf""#, nil), ("null", nil), ("{}", nil),
    ] as [(String, Double?)])
    func decodesSeriesIndexAsStringOrNumber(json: String, index: Double?) throws {
        let book = try decoder.decode(BookOrbitBook.self, from: Data(#"{"id":1,"title":"T","seriesIndex":\#(json)}"#.utf8))
        #expect(book.seriesIndex == index)
    }

    @Test func decodesNullTitleAsEmpty() throws {
        let book = try decoder.decode(BookOrbitBook.self, from: Data(#"{"id":1,"title":null}"#.utf8))
        #expect(book.title == "")
    }

    @Test func decodesCollectionPage() throws {
        let json = #"""
        {"items":[{"id":1,"title":"Frankenstein","authors":["Mary Wollstonecraft Shelley"],"files":[]}],
         "total":5,"page":0,"size":1}
        """#
        let page = try decoder.decode(BookOrbitPage<BookOrbitBook>.self, from: Data(json.utf8))
        #expect(page.items.map(\.title) == ["Frankenstein"])
        #expect(page.total == 5)
        #expect(page.page == 0)
    }

    @Test func decodesLibrariesAndCollections() throws {
        let libraries = try decoder.decode([BookOrbitLibrary].self, from: Data(#"""
        [{"id":1,"type":"books","name":"Spike","icon":"BookOpen","bookCount":5,"folders":[{"id":1,"path":"/books/spike"}]}]
        """#.utf8))
        #expect(libraries == [BookOrbitLibrary(id: 1, name: "Spike", type: "books", icon: "BookOpen", bookCount: 5)])

        let collections = try decoder.decode([BookOrbitCollection].self, from: Data(#"""
        [{"id":1,"userId":1,"mediaType":"books","name":"Spike","icon":"Rocket","description":null,
          "isPublic":false,"bookCount":5,"isOwner":true}]
        """#.utf8))
        #expect(collections.first?.name == "Spike")
        #expect(collections.first?.bookCount == 5)
        #expect(collections.first?.description == nil)
    }

    @Test func parsesDatesWithAndWithoutMilliseconds() throws {
        let json = #"""
        {"accessToken":"a","accessTokenExpiresAt":"2026-10-31T15:58:53.000Z",
         "refreshToken":"r","refreshTokenExpiresAt":"2026-11-07T15:43:53Z"}
        """#
        let body = try decoder.decode(LoginResponse.self, from: Data(json.utf8))
        #expect(body.accessTokenExpiresAt == Date(timeIntervalSince1970: 1_793_462_333))
        #expect(body.refreshTokenExpiresAt == Date(timeIntervalSince1970: 1_794_066_233))
    }

    // MARK: Progress

    @Test func mapsStoredProgressToReadingPosition() throws {
        let json = #"""
        {"cfi":"epubcfi(/6/8!/4/2/2[chapter001]/1:0)","pageNumber":null,"positionSeconds":null,
         "percentage":42.5,"koreaderProgress":null,"textUpdatedAt":"2026-10-31T15:44:33.977Z"}
        """#
        let progress = try #require(try decoder.decode(ProgressResponse.self, from: Data(json.utf8)).progress)
        #expect(progress.position == ReadingPosition(cfi: "epubcfi(/6/8!/4/2/2[chapter001]/1:0)", fraction: 0.425))
        #expect(progress.updatedAt != nil)
    }

    @Test func treatsNeverOpenedFileAsNoProgress() throws {
        let json = #"""
        {"cfi":null,"pageNumber":null,"positionSeconds":null,"percentage":0,"textUpdatedAt":null}
        """#
        #expect(try decoder.decode(ProgressResponse.self, from: Data(json.utf8)).progress == nil)
    }

    @Test func keepsPageNumberForFixedLayout() throws {
        let json = #"{"cfi":null,"pageNumber":12,"percentage":40}"#
        let progress = try #require(try decoder.decode(ProgressResponse.self, from: Data(json.utf8)).progress)
        #expect(progress.position == ReadingPosition(fraction: 0.4, pageNumber: 12))
        #expect(progress.updatedAt == nil)
    }

    @Test(arguments: [
        (0.0, 0.0), (0.25, 25.0), (1.0, 100.0), (1.7, 100.0), (-0.2, 0.0), (Double.nan, 0.0),
    ])
    func convertsFractionToPercentage(fraction: Double, percentage: Double) {
        #expect(BookOrbitProgress.percentage(fromFraction: fraction) == percentage)
    }

    @Test func encodesSaveRequestWithoutNilFields() throws {
        let request = SaveProgressRequest(ReadingPosition(cfi: "epubcfi(/6/4!/4/2/1:0)", fraction: 0.5))
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(object["cfi"] as? String == "epubcfi(/6/4!/4/2/1:0)")
        #expect(object["percentage"] as? Double == 50)
        #expect(object["pageNumber"] == nil)
        #expect(object.count == 2)
    }

    @Test func readsBookOrbitErrorMessages() throws {
        let single = try decoder.decode(ErrorResponse.self, from: Data(#"{"statusCode":404,"message":"Book not found"}"#.utf8))
        #expect(single.message == "Book not found")
        let list = try decoder.decode(ErrorResponse.self, from: Data(#"""
        {"statusCode":400,"message":["percentage must not be greater than 100","cfi must be a string"]}
        """#.utf8))
        #expect(list.message == "percentage must not be greater than 100; cfi must be a string")
    }
}
