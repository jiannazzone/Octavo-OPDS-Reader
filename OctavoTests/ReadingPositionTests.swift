import Foundation
import OctavoKit
import Testing

struct ReadingPositionTests {
    @Test func roundTripsThroughJSON() throws {
        let position = ReadingPosition(cfi: "epubcfi(/6/14!/4/2/1:0)", fraction: 0.25)
        let data = try JSONEncoder().encode(position)
        #expect(try JSONDecoder().decode(ReadingPosition.self, from: data) == position)
    }
}
