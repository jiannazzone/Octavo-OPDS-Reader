import Foundation
import OctavoKit
import Testing

struct ReadingPositionTests {
    @Test func omitsMissingFieldsInJSON() throws {
        let position = ReadingPosition(fraction: 0.5)
        let json = try #require(String(data: JSONEncoder().encode(position), encoding: .utf8))
        #expect(json == #"{"fraction":0.5}"#)
    }
}
