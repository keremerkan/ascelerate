import Testing
@testable import AscelerateCore

/// Apple's rules for a price's volume tiers, checked before a price is sent.
@Suite struct VolumeTierTests {
  private func tier(_ minQuantity: Int, _ price: String) -> Subscriptions.VolumeTier {
    .init(minQuantity: minQuantity, pricePointID: "p\(minQuantity)", customerPrice: price)
  }

  @Test func validTiers() throws {
    try Subscriptions.validate(singleSeatPrice: "9.99", tiers: [])
    try Subscriptions.validate(singleSeatPrice: "9.99", tiers: [tier(2, "8.99"), tier(10, "7.99"), tier(50, "6.99"), tier(100, "5.99")])
  }

  @Test func tooMany() {
    #expect(throws: Subscriptions.VolumeTierError.tooMany) {
      try Subscriptions.validate(
        singleSeatPrice: "9.99", tiers: [tier(2, "8.99"), tier(3, "7.99"), tier(4, "6.99"), tier(5, "5.99"), tier(6, "4.99")])
    }
  }

  @Test func firstTierFromTwoSeats() {
    #expect(throws: Subscriptions.VolumeTierError.firstBelowTwo) {
      try Subscriptions.validate(singleSeatPrice: "9.99", tiers: [tier(1, "8.99")])
    }
  }

  @Test func ascendingSeatCounts() {
    #expect(throws: Subscriptions.VolumeTierError.notAscending) {
      try Subscriptions.validate(singleSeatPrice: "9.99", tiers: [tier(10, "7.99"), tier(2, "8.99")])
    }
    #expect(throws: Subscriptions.VolumeTierError.notAscending) {
      try Subscriptions.validate(singleSeatPrice: "9.99", tiers: [tier(2, "8.99"), tier(2, "7.99")])
    }
  }

  @Test func eachTierCheaper() {
    // Against the single seat, and against the tier before it; equal counts as not cheaper.
    #expect(throws: Subscriptions.VolumeTierError.notDecreasing(minQuantity: 2)) {
      try Subscriptions.validate(singleSeatPrice: "9.99", tiers: [tier(2, "9.99")])
    }
    #expect(throws: Subscriptions.VolumeTierError.notDecreasing(minQuantity: 10)) {
      try Subscriptions.validate(singleSeatPrice: "9.99", tiers: [tier(2, "8.99"), tier(10, "9.49")])
    }
  }
}
