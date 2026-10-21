import Testing
@testable import AscelerateCore

/// The price schedule edits: what's sent again when the base price, a manual price or a planned
/// change is changed.
@Suite struct AppPricingTests {
  static let later = "2099-01-01"

  static func price(
    _ territory: String, _ tier: String, start: String? = nil, end: String? = nil, manual: Bool = true
  ) -> AppPricing.Price {
    AppPricing.Price(
      id: "\(territory)-\(tier)-\(start ?? "")",
      point: AppPricing.PricePoint(id: "\(territory)-\(tier)", territoryID: territory, customerPrice: tier, proceeds: tier),
      manual: manual, startDate: start, endDate: end)
  }

  static func schedule(_ prices: [AppPricing.Price]) -> AppPricing.Schedule {
    AppPricing.Schedule(baseTerritoryID: "USA", manualPrices: prices, automaticPrices: [], currencies: [:])
  }

  static func sent(_ prices: [AppPricing.NewPrice]) -> [String] {
    prices.map { "\($0.pricePointID) \($0.startDate ?? "-") \($0.endDate ?? "-")" }
  }

  @Test func endedPricesAreLeftOutAndCurrentOnesLoseTheirStart() {
    let schedule = Self.schedule([
      Self.price("USA", "0.99", end: "2000-01-01"),
      Self.price("USA", "1.99", start: "2000-01-01"),
    ])
    #expect(Self.sent(schedule.newPrices) == ["USA-1.99 - -"])
  }

  @Test func baseChangeNowKeepsOrDropsTheOthers() {
    let schedule = Self.schedule([Self.price("USA", "0.99"), Self.price("DEU", "1.99")])
    #expect(Self.sent(schedule.changingBase(to: "USA", pricePointID: "USA-2.99", from: nil, keepingOthers: true))
      == ["DEU-1.99 - -", "USA-2.99 - -"])
    #expect(Self.sent(schedule.changingBase(to: "USA", pricePointID: "USA-2.99", from: nil, keepingOthers: false))
      == ["USA-2.99 - -"])
  }

  @Test func datedBaseChangeEndsTheCurrentPrice() {
    let schedule = Self.schedule([Self.price("USA", "0.99"), Self.price("DEU", "1.99")])
    #expect(Self.sent(schedule.changingBase(to: "USA", pricePointID: "USA-2.99", from: Self.later, keepingOthers: true))
      == ["USA-0.99 - \(Self.later)", "DEU-1.99 - -", "USA-2.99 \(Self.later) -"])
    #expect(Self.sent(schedule.changingBase(to: "USA", pricePointID: "USA-2.99", from: Self.later, keepingOthers: false))
      == ["USA-0.99 - \(Self.later)", "DEU-1.99 - \(Self.later)", "USA-2.99 \(Self.later) -"])
  }

  @Test func newBaseTerritoryReplacesTheOldBasePrice() {
    let schedule = Self.schedule([Self.price("USA", "0.99"), Self.price("DEU", "1.99")])
    #expect(Self.sent(schedule.changingBase(to: "DEU", pricePointID: "DEU-2.99", from: nil, keepingOthers: true))
      == ["DEU-2.99 - -"])
  }

  @Test func removingAPlannedPriceExtendsTheOneBefore() {
    let schedule = Self.schedule([
      Self.price("USA", "0.99", end: Self.later),
      Self.price("USA", "2.99", start: Self.later),
    ])
    #expect(Self.sent(schedule.removingPlanned(schedule.manualPrices[1])) == ["USA-0.99 - -"])
  }

  @Test func manualPricesAreSetAndRemoved() {
    let schedule = Self.schedule([Self.price("USA", "0.99"), Self.price("DEU", "1.99")])
    #expect(Self.sent(schedule.settingManual(territoryID: "DEU", pricePointID: "DEU-2.99"))
      == ["USA-0.99 - -", "DEU-2.99 - -"])
    #expect(Self.sent(schedule.settingManual(territoryID: "FRA", pricePointID: "FRA-2.99"))
      == ["USA-0.99 - -", "DEU-1.99 - -", "FRA-2.99 - -"])
    #expect(Self.sent(schedule.removingManual(territoryID: "DEU")) == ["USA-0.99 - -"])
  }

  @Test func currentAutomaticPricesAreKeptByHand() {
    let schedule = AppPricing.Schedule(
      baseTerritoryID: "USA", manualPrices: [Self.price("USA", "0.99"), Self.price("DEU", "1.99")],
      automaticPrices: [Self.price("FRA", "1.09", manual: false), Self.price("DEU", "1.09", manual: false)],
      currencies: [:])
    #expect(Self.sent(schedule.keepingCurrent(territoryIDs: ["FRA", "DEU"]))
      == ["USA-0.99 - -", "DEU-1.99 - -", "FRA-1.09 - -"])
  }

  @Test func baseManualPriceIsNeverRemoved() {
    let schedule = Self.schedule([Self.price("USA", "0.99"), Self.price("DEU", "1.99")])
    #expect(Self.sent(schedule.removingManual(territoryIDs: ["USA", "DEU"])) == ["USA-0.99 - -"])
  }

  @Test func temporaryChangeCutsManualPricesAndLeavesAppleAfter() {
    let schedule = Self.schedule([Self.price("USA", "0.99"), Self.price("DEU", "1.99")])
    let sent = Self.sent(schedule.addingTemporary(
      pricePointIDs: ["USA": "USA-0.49", "FRA": "FRA-0.49"], from: "2099-01-01", until: "2099-01-08"))
    #expect(sent == [
      "USA-0.99 - 2099-01-01", "USA-0.99 2099-01-08 -", "DEU-1.99 - -",
      "FRA-0.49 2099-01-01 2099-01-08", "USA-0.49 2099-01-01 2099-01-08",
    ])
  }
}
