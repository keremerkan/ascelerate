import Foundation
import Testing
@testable import AscelerateCore

/// A group without one of its subscriptions.
@Suite struct SubscriptionGroupTests {
  let group: Subscriptions.Group = try! JSONDecoder().decode(Subscriptions.Group.self, from: Data("""
    {"id": "G", "referenceName": "Pro", "subscriptions": [
      {"id": "1", "productID": "pro.month", "name": "Monthly", "state": "APPROVED", "level": 1},
      {"id": "2", "productID": "pro.year", "name": "Yearly", "state": "APPROVED", "level": 1},
      {"id": "3", "productID": "pro.week", "name": "Weekly", "state": "READY_TO_SUBMIT", "level": 2}
    ]}
    """.utf8))

  @Test func removingTakesOutOnlyThatSubscription() {
    let without = group.removing(subscriptionID: "2")
    #expect(without.subscriptions.map(\.id) == ["1", "3"])
    #expect(without.id == "G" && without.referenceName == "Pro")
    // The original is unchanged; an unknown ID changes nothing.
    #expect(group.subscriptions.count == 3)
    #expect(group.removing(subscriptionID: "9") == group)
  }
}
