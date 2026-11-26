import Foundation
import Testing
@testable import AscelerateCore

@Suite struct ReviewSubmissionItemTests {
  @Test func theVersionIDRoundTripsAndOldRecordsDecodeWithout() throws {
    let item = ReviewSubmissions.Item(
      id: "I1", state: "READY_FOR_REVIEW", kind: "appStoreVersion", name: "2.0", platform: "IOS", build: nil,
      appStoreVersionID: "V1")
    let decoded = try JSONDecoder().decode(ReviewSubmissions.Item.self, from: JSONEncoder().encode(item))
    #expect(decoded.appStoreVersionID == "V1")
    // Saved before the field existed: decodes, without an ID.
    let old = #"{"id":"I2","kind":"appEvent","name":"Launch"}"#
    #expect(try JSONDecoder().decode(ReviewSubmissions.Item.self, from: Data(old.utf8)).appStoreVersionID == nil)
    // Other kinds carry none.
    #expect(ReviewSubmissions.Item(id: "I3", state: nil, kind: "appEvent", name: nil, platform: nil, build: nil).appStoreVersionID == nil)
  }
}
