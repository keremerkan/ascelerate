import Foundation
import Testing
import AppleAdsClient
@testable import AscelerateAds

/// Amounts as Apple takes them.
@Suite struct MoneyTests {
  @Test func decimalAmountsAreSentExactly() {
    #expect(Components.Schemas.Money(decimal: Decimal(string: "0.5")!, currency: "USD").amount == "0.5")
    #expect(Components.Schemas.Money(decimal: Decimal(string: "150")!, currency: "USD").amount == "150")
    #expect(Components.Schemas.Money(decimal: Decimal(string: "1.25")!, currency: "EUR").amount == "1.25")
  }

  @Test func literalsAndDoublesStillTakeTheDoubleForm() {
    let bid = 0.6
    #expect(Components.Schemas.Money(bid, currency: "USD").amount == "0.6")
    #expect(Components.Schemas.Money(150, currency: "USD").amount == "150")
    #expect(Components.Schemas.Money(0.25, currency: "USD").amount == "0.25")
  }
}
