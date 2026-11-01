import Foundation
import OctavoKit
import Testing
@testable import Octavo

struct ReaderMessageTests {
    // A relocate message as bridge.js posted it while reading Pride and Prejudice.
    static let relocateJSON = """
    {"type":"relocate","cfi":"epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)","fraction":0.011097344942887005,\
    "tocLabel":"PRIDE. and PREJUDICE","sectionIndex":1,"sectionCount":64,"location":{"current":5,"total":581}}
    """

    @Test func decodesReady() throws {
        #expect(try ReaderMessage.decode(#"{"type":"ready"}"#) == .ready)
    }

    @Test func decodesViewport() throws {
        #expect(try ReaderMessage.decode(#"{"type":"viewport","width":951,"height":493}"#) == .viewport(width: 951, height: 493))
    }

    @Test func decodesRelocate() throws {
        let message = try ReaderMessage.decode(Self.relocateJSON)
        guard case .relocate(let relocation) = message else {
            Issue.record("Expected relocate, got \(message)")
            return
        }
        #expect(relocation.cfi == "epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)")
        #expect(relocation.fraction == 0.011097344942887005)
        #expect(relocation.tocLabel == "PRIDE. and PREJUDICE")
        #expect(relocation.sectionIndex == 1)
        #expect(relocation.sectionCount == 64)
        #expect(relocation.location == .init(current: 5, total: 581))
    }

    @Test func relocateMapsToReadingPosition() throws {
        guard case .relocate(let relocation) = try ReaderMessage.decode(Self.relocateJSON) else {
            Issue.record("Expected relocate")
            return
        }
        #expect(relocation.position == ReadingPosition(
            cfi: "epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)",
            fraction: 0.011097344942887005
        ))
    }

    @Test func relocatePicksTheCFIShapeToSync() throws {
        let json = #"{"type":"relocate","cfi":"epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)","startCFI":"epubcfi(/6/4!/4/16/8/2/2/2/3:0)","blankPage":false,"fraction":0.25}"#
        guard case .relocate(let relocation) = try ReaderMessage.decode(json) else {
            Issue.record("Expected relocate")
            return
        }
        #expect(relocation.blankPage == false)
        #expect(relocation.position(.point) == ReadingPosition(cfi: "epubcfi(/6/4!/4/16/8/2/2/2/3:0)", fraction: 0.25))
        #expect(relocation.position(.range) == ReadingPosition(cfi: "epubcfi(/6/4!/4/16/8/2,/2/2/3:0,/4/2/3:14)", fraction: 0.25))
    }

    // A bridge from before sync sends no start point; the range stands in.
    @Test func pointFallsBackToTheRange() throws {
        guard case .relocate(let relocation) = try ReaderMessage.decode(Self.relocateJSON) else {
            Issue.record("Expected relocate")
            return
        }
        #expect(relocation.startCFI == nil)
        #expect(relocation.blankPage == nil)
        #expect(relocation.position(.point).cfi == relocation.cfi)
    }

    @Test func decodesABlankPage() throws {
        let json = #"{"type":"relocate","cfi":"epubcfi(/6/4!/4,/0,/0)","startCFI":"epubcfi(/6/4!/4/0)","blankPage":true,"fraction":0.0135}"#
        guard case .relocate(let relocation) = try ReaderMessage.decode(json) else {
            Issue.record("Expected relocate")
            return
        }
        #expect(relocation.blankPage == true)
    }

    // foliate can report NaN (JSON null) while a section is still being measured.
    @Test func relocateToleratesNullsAndMissingFields() throws {
        let json = #"{"type":"relocate","cfi":"epubcfi(/6/2!/4/2,,/2/2)","fraction":null,"location":{"current":null,"total":581}}"#
        guard case .relocate(let relocation) = try ReaderMessage.decode(json) else {
            Issue.record("Expected relocate")
            return
        }
        #expect(relocation.fraction == nil)
        #expect(relocation.tocLabel == nil)
        #expect(relocation.sectionIndex == nil)
        #expect(relocation.location == .init(current: nil, total: 581))
        #expect(relocation.position == ReadingPosition(cfi: "epubcfi(/6/2!/4/2,,/2/2)", fraction: 0))
    }

    @Test(arguments: [(1.2, 1.0), (-0.1, 0.0), (0.5, 0.5)])
    func relocateClampsFraction(reported: Double, expected: Double) throws {
        let json = #"{"type":"relocate","cfi":null,"fraction":\#(reported)}"#
        guard case .relocate(let relocation) = try ReaderMessage.decode(json) else {
            Issue.record("Expected relocate")
            return
        }
        #expect(relocation.position == ReadingPosition(cfi: nil, fraction: expected))
    }

    @Test func decodesOpened() throws {
        let json = #"{"type":"opened","restoredFrom":"cfi","title":"Pride and Prejudice","sectionCount":64,"isFixedLayout":false}"#
        #expect(try ReaderMessage.decode(json) == .opened(.init(
            restoredFrom: "cfi", title: "Pride and Prejudice", sectionCount: 64, isFixedLayout: false
        )))
    }

    @Test func decodesErrorWithOnlyAMessage() throws {
        let json = #"{"type":"error","phase":"open","message":"Couldn't load the book (404)"}"#
        #expect(try ReaderMessage.decode(json) == .error(.init(phase: "open", message: "Couldn't load the book (404)")))
    }

    @Test func decodesScriptErrorDetails() throws {
        let json = #"{"type":"error","phase":"script","message":"TypeError: x is undefined","source":"octavo://app/bridge.js","line":42}"#
        guard case .error(let error) = try ReaderMessage.decode(json) else {
            Issue.record("Expected error")
            return
        }
        #expect(error.source == "octavo://app/bridge.js")
        #expect(error.line == 42)
    }

    @Test func decodesLogAndTap() throws {
        #expect(try ReaderMessage.decode(#"{"type":"log","level":"warn","message":"Failed to load section 3"}"#)
            == .log(level: "warn", message: "Failed to load section 3"))
        #expect(try ReaderMessage.decode(#"{"type":"tap","zone":"middle"}"#) == .tap(zone: "middle"))
        #expect(try ReaderMessage.decode(#"{"type":"tap"}"#) == .tap(zone: "middle"))
        #expect(try ReaderMessage.decode(#"{"type":"tap","zone":"column"}"#) == .tap(zone: "column"))
    }

    @Test func decodesExternalLink() throws {
        #expect(try ReaderMessage.decode(#"{"type":"externalLink","href":"https://www.gutenberg.org/ebooks/1342"}"#)
            == .externalLink(href: "https://www.gutenberg.org/ebooks/1342"))
    }

    @Test func unknownTypeIsNotAnError() throws {
        #expect(try ReaderMessage.decode(#"{"type":"selection","text":"Mr. Darcy"}"#) == .unknown(type: "selection"))
    }

    @Test func rejectsNonStringBodies() {
        #expect(throws: ReaderMessage.DecodingError.notAString) {
            try ReaderMessage.decode(["type": "ready"])
        }
    }

    @Test(arguments: ["not json", #"{"cfi":"epubcfi(/6/2!/4)"}"#, #"{"type":"opened"}"#])
    func rejectsMalformedMessages(json: String) {
        #expect(throws: (any Error).self) {
            try ReaderMessage.decode(json)
        }
    }
}
