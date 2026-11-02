import Foundation
import Testing
@testable import Octavo

/// Search in book (decision 19): what's worth searching, results arriving a
/// section at a time, grouping by chapter, and stepping through.
@MainActor
struct ReaderSearchTests {
    private func match(_ chapter: String?, _ cfi: String = "epubcfi(/6/4!/4/2/1:0)") -> ReaderSearch.Match {
        ReaderSearch.Match(cfi: cfi, pre: "the ", match: "whale", post: " rose", chapter: chapter, fraction: 0.1)
    }

    @Test func twoCharactersSearchAsYouTypeOneOnReturn() {
        let search = ReaderSearch()
        search.query = " a "
        #expect(search.searchable(submitted: false) == nil)
        #expect(search.searchable(submitted: true) == "a")
        search.query = "  "
        #expect(search.searchable(submitted: true) == nil)
        search.query = "Queequeg"
        #expect(search.searchable(submitted: false) == "Queequeg")
    }

    @Test func resultsArriveForTheCurrentSearchOnly() {
        let search = ReaderSearch()
        let old = search.begin("whale")
        let new = search.begin("white whale")
        search.receive(.init(token: old, matches: [match("CHAPTER 1.")], done: false, truncated: false))
        #expect(search.matches.isEmpty)

        search.receive(.init(token: new, matches: [match("CHAPTER 31.")], done: false, truncated: false))
        #expect(search.isSearching)
        search.receive(.init(token: new, matches: [match("CHAPTER 36.")], done: true, truncated: true))
        #expect(search.matches.count == 2)
        #expect(!search.isSearching)
        #expect(search.isTruncated)
        #expect(search.searched == "white whale")
    }

    @Test func matchesGroupByChapterInTheBooksOrder() {
        let search = ReaderSearch()
        let token = search.begin("Queequeg")
        search.receive(.init(token: token, matches: [match(nil), match("3."), match("3."), match("4."), match("3.")], done: true, truncated: false))
        let groups = search.groups
        #expect(groups.map(\.chapter) == [nil, "3.", "4.", "3."])
        #expect(groups.map { $0.items.map(\.index) } == [[0], [1, 2], [3], [4]])
    }

    // The crash Adam hit (2026-11-02): a second search emptied the matches
    // while rows from the first were still being drawn, and they looked
    // their match up by index. Rows now hold their match, and a new search's
    // rows have new IDs.
    @Test func rowsKeepTheirMatchAndANewSearchGetsNewRows() {
        let search = ReaderSearch()
        let first = search.begin("eat")
        search.receive(.init(token: first, matches: [match("I."), match("II.")], done: true, truncated: false))
        let old = search.groups.flatMap(\.items)

        let second = search.begin("scientific")
        #expect(search.groups.isEmpty)
        #expect(old.map(\.match.match) == ["whale", "whale"])
        search.receive(.init(token: second, matches: [match("I.")], done: true, truncated: false))
        #expect(Set(search.groups.flatMap(\.items).map(\.id)).isDisjoint(with: old.map(\.id)))
    }

    @Test func steppingStopsAtEachEnd() {
        let search = ReaderSearch()
        let token = search.begin("whale")
        search.receive(.init(token: token, matches: [match("1."), match("1."), match("2.")], done: true, truncated: false))
        #expect(!search.isStepping)
        search.show(0)
        #expect(search.isStepping && !search.canGoBack && search.canGoForward)
        search.show(2)
        #expect(search.canGoBack && !search.canGoForward)
        search.show(7)
        #expect(search.current == 2)
    }

    @Test func endingForgetsTheQueryClearingKeepsIt() {
        let search = ReaderSearch()
        search.query = "whale"
        let token = search.begin("whale")
        search.receive(.init(token: token, matches: [match("1.")], done: true, truncated: false))
        search.show(0)

        search.clear()
        #expect(search.query == "whale")
        #expect(search.matches.isEmpty && !search.isStepping && search.searched == nil)

        search.end()
        #expect(search.query.isEmpty)
        // A batch from before still finds nothing to join.
        search.receive(.init(token: token, matches: [match("1.")], done: true, truncated: false))
        #expect(search.matches.isEmpty)
    }

    @Test func decodesABatch() throws {
        let json = #"{"type":"searchResults","token":3,"matches":[{"cfi":"epubcfi(/6/4!/4/58/1:4)","pre":"…go to sleep. ","match":"Queequeg","post":", look here","chapter":"CHAPTER 3. The Spouter-Inn.","fraction":0.0748}],"done":false,"truncated":false}"#
        guard case .searchResults(let batch) = try ReaderMessage.decode(json) else {
            Issue.record("Expected searchResults")
            return
        }
        #expect(batch.token == 3)
        #expect(batch.matches.first?.match == "Queequeg")
        #expect(batch.matches.first?.chapter == "CHAPTER 3. The Spouter-Inn.")
    }
}
