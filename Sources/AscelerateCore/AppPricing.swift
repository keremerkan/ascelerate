import ASCKit
import Foundation

/// An app's price schedule (`appPriceSchedules`): its base territory, the prices set by hand
/// (manual) and the ones Apple derives from the base price for every other territory (automatic),
/// each from a start date to an end date. A schedule is replaced as a whole.
public enum AppPricing {
  /// One of a territory's price tiers.
  public struct PricePoint: Sendable, Hashable, Identifiable {
    public let id: String
    public let territoryID: String
    /// What the customer pays, in the territory's currency ("0.99").
    public let customerPrice: String
    /// What the developer gets.
    public let proceeds: String
  }

  /// A price in the schedule.
  public struct Price: Sendable, Hashable, Identifiable {
    public let id: String
    public let point: PricePoint
    /// Set by hand, or derived by Apple from the base price.
    public let manual: Bool
    /// The first day it applies (yyyy-MM-dd); nil from the start.
    public let startDate: String?
    /// The day it stops applying (yyyy-MM-dd); nil for good.
    public let endDate: String?

    public var territoryID: String { point.territoryID }

    /// Whether it applies on the day (yyyy-MM-dd).
    public func applies(on day: String) -> Bool {
      (startDate ?? "") <= day && endDate.map { day < $0 } ?? true
    }
  }

  public struct Schedule: Sendable, Hashable {
    public let baseTerritoryID: String
    public let manualPrices: [Price]
    public let automaticPrices: [Price]
    /// Each territory's currency code.
    public let currencies: [String: String]
  }

  /// Today in UTC (yyyy-MM-dd), the day price dates are compared with.
  public static var today: String {
    Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
  }

  /// A manual price for `setSchedule`.
  public struct NewPrice: Sendable, Hashable {
    public let pricePointID: String
    public let startDate: String?
    public let endDate: String?

    public init(pricePointID: String, startDate: String? = nil, endDate: String? = nil) {
      self.pricePointID = pricePointID
      self.startDate = startDate
      self.endDate = endDate
    }
  }

  /// The app's price schedule; nil when it has no price yet (App Store Connect's Add Pricing).
  public static func schedule(appID: String, client: ASCClient) async throws -> Schedule? {
    let schedule = try await optionalRelated {
      try await withTransientRetry {
        try await client.appsAppPriceScheduleGetToOneRelated(
          path: .init(id: appID),
          query: .init(fieldsAppPriceSchedules: [.baseTerritory], include: [.baseTerritory])
        ).ok.body.json.data
      }
    }
    guard let schedule, let base = schedule.relationships?.baseTerritory?.data?.id else { return nil }
    // A new app's schedule has a base territory (USA) but no prices: listing them answers 404
    // ("There is no resource of type 'null'", seen 2026-10-21).
    async let manual = optionalRelated { try await prices(scheduleID: schedule.id, automatic: false, client: client) }
    async let automatic = optionalRelated { try await prices(scheduleID: schedule.id, automatic: true, client: client) }
    guard let (manualPrices, manualCurrencies) = try await manual, !manualPrices.isEmpty else { return nil }
    let (automaticPrices, automaticCurrencies) = try await automatic ?? ([], [:])
    return Schedule(
      baseTerritoryID: base, manualPrices: manualPrices, automaticPrices: automaticPrices,
      currencies: manualCurrencies.merging(automaticCurrencies) { first, _ in first })
  }

  /// A schedule's manual or automatic prices, with each territory's currency.
  private static func prices(
    scheduleID: String, automatic: Bool, client: ASCClient
  ) async throws -> ([Price], [String: String]) {
    let pages = try await withTransientRetry {
      if automatic {
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.appPriceSchedulesAutomaticPricesGetToManyRelated(
            path: .init(id: scheduleID),
            query: .init(
              fieldsAppPricePoints: [.customerPrice, .proceeds, .territory], limit: 200,
              include: [.appPricePoint, .territory])
          ).ok.body.json
        }.map { ($0.data, $0.included ?? []) }
      } else {
        try await ASCPaging.allPages(next: { $0.links.next }) {
          try await client.appPriceSchedulesManualPricesGetToManyRelated(
            path: .init(id: scheduleID),
            query: .init(
              fieldsAppPricePoints: [.customerPrice, .proceeds, .territory], limit: 200,
              include: [.appPricePoint, .territory])
          ).ok.body.json
        }.map { ($0.data, $0.included ?? []) }
      }
    }
    var points: [String: Components.Schemas.AppPricePointV3] = [:]
    var currencies: [String: String] = [:]
    for included in pages.flatMap(\.1) {
      switch included {
        case .appPricePoints(let point): points[point.id] = point
        case .territories(let territory): currencies[territory.id] = territory.attributes?.currency
      }
    }
    let prices = pages.flatMap(\.0).compactMap { price -> Price? in
      guard let territoryID = price.relationships?.territory?.data?.id,
        let pointID = price.relationships?.appPricePoint?.data?.id, let point = points[pointID]
      else { return nil }
      return Price(
        id: price.id, point: pricePoint(point, territoryID: territoryID), manual: price.attributes?.manual ?? !automatic,
        startDate: price.attributes?.startDate, endDate: price.attributes?.endDate)
    }
    return (prices, currencies)
  }

  private static func pricePoint(_ point: Components.Schemas.AppPricePointV3, territoryID: String) -> PricePoint {
    PricePoint(
      id: point.id, territoryID: territoryID, customerPrice: point.attributes?.customerPrice ?? "",
      proceeds: point.attributes?.proceeds ?? "")
  }

  /// Every territory's currency code.
  public static func currencies(client: ASCClient) async throws -> [String: String] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.territoriesGetCollection(query: .init(fieldsTerritories: [.currency], limit: 200)).ok.body.json
      }
    }.flatMap(\.data).reduce(into: [:]) { $0[$1.id] = $1.attributes?.currency }
  }

  /// A territory's price tiers, cheapest first (free is the first).
  public static func pricePoints(appID: String, territoryID: String, client: ASCClient) async throws -> [PricePoint] {
    try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appsAppPricePointsGetToManyRelated(
          path: .init(id: appID),
          query: .init(filterTerritory: [territoryID], fieldsAppPricePoints: [.customerPrice, .proceeds], limit: 200)
        ).ok.body.json
      }
    }.flatMap(\.data).map { pricePoint($0, territoryID: territoryID) }
      .sorted { (Decimal(string: $0.customerPrice) ?? 0) < (Decimal(string: $1.customerPrice) ?? 0) }
  }

  /// What a tier comes to in every other territory: the prices Apple derives from a base price,
  /// with each territory's currency.
  public static func equalizations(
    of pricePointID: String, client: ASCClient
  ) async throws -> (points: [PricePoint], currencies: [String: String]) {
    let pages = try await withTransientRetry {
      try await ASCPaging.allPages(next: { $0.links.next }) {
        try await client.appPricePointsV3EqualizationsGetToManyRelated(
          path: .init(id: pricePointID),
          query: .init(fieldsAppPricePoints: [.customerPrice, .proceeds, .territory], limit: 200, include: [.territory])
        ).ok.body.json
      }
    }
    var currencies: [String: String] = [:]
    for page in pages {
      for case .territories(let territory) in page.included ?? [] {
        currencies[territory.id] = territory.attributes?.currency
      }
    }
    let points = pages.flatMap(\.data).compactMap { point -> PricePoint? in
      guard let territoryID = point.relationships?.territory?.data?.id else { return nil }
      return pricePoint(point, territoryID: territoryID)
    }
    return (points, currencies)
  }

  /// Replaces the app's price schedule: the base territory and every manual price (the base
  /// territory's included). Territories without a manual price get Apple's automatic prices.
  public static func setSchedule(
    appID: String, baseTerritoryID: String, manualPrices: [NewPrice], client: ASCClient
  ) async throws {
    let localIDs = manualPrices.indices.map { "${price\($0)}" }
    let request = Components.Schemas.AppPriceScheduleCreateRequest(
      data: .init(
        relationships: .init(
          app: .init(data: .init(id: appID, _type: "apps")),
          baseTerritory: .init(data: .init(id: baseTerritoryID, _type: "territories")),
          manualPrices: .init(data: localIDs.map { .init(id: $0, _type: "appPrices") })),
        _type: "appPriceSchedules"),
      included: zip(localIDs, manualPrices).map { localID, price in
        .AppPriceV2InlineCreate(.init(
          attributes: .init(endDate: price.endDate, startDate: price.startDate),
          id: localID,
          relationships: .init(appPricePoint: .init(data: .init(id: price.pricePointID, _type: "appPricePoints"))),
          _type: "appPrices"))
      })
    _ = try await withTransientRetry {
      try await client.appPriceSchedulesCreateInstance(body: .json(request)).created
    }
  }
}

extension AppPricing.Schedule {
  /// The schedule's manual prices as `setSchedule` takes them again: the ones that ended are left
  /// out, and the ones that apply now are sent without their start date.
  public var newPrices: [AppPricing.NewPrice] {
    let today = AppPricing.today
    return manualPrices.compactMap { price in
      if let end = price.endDate, end <= today { return nil }
      let startsLater = price.startDate.map { $0 > today } ?? false
      return AppPricing.NewPrice(
        pricePointID: price.point.id, startDate: startsLater ? price.startDate : nil, endDate: price.endDate)
    }
  }

  /// The base price changed to a tier of `territoryID` (which becomes the base territory) from the
  /// day (yyyy-MM-dd; nil for now), the base territory's later prices dropped. A dated change keeps
  /// the base territory. Without `keepingOthers`, the other territories' manual prices end that day
  /// too and Apple's automatic prices take over.
  public func changingBase(
    to territoryID: String, pricePointID: String, from day: String?, keepingOthers: Bool
  ) -> [AppPricing.NewPrice] {
    let bases: Set<String> = [baseTerritoryID, territoryID]
    let kept = zip(manualPrices.filter(\.isCurrentOrLater), newPrices).compactMap { price, new -> AppPricing.NewPrice? in
      guard bases.contains(price.territoryID) || !keepingOthers else { return new }
      return Self.ending(new, on: day)
    }
    return kept + [AppPricing.NewPrice(pricePointID: pricePointID, startDate: day)]
  }

  /// A territory's manual price set to a tier from now on, its later prices dropped.
  public func settingManual(territoryID: String, pricePointID: String) -> [AppPricing.NewPrice] {
    removingManual(territoryID: territoryID) + [AppPricing.NewPrice(pricePointID: pricePointID)]
  }

  /// A territory's manual prices removed: Apple's automatic price applies there.
  public func removingManual(territoryID: String) -> [AppPricing.NewPrice] {
    removingManual(territoryIDs: [territoryID])
  }

  /// Territories' manual prices removed (the base territory's stay): Apple's automatic prices
  /// apply there.
  public func removingManual(territoryIDs: Set<String>) -> [AppPricing.NewPrice] {
    zip(manualPrices.filter(\.isCurrentOrLater), newPrices)
      .filter { $0.0.territoryID == baseTerritoryID || !territoryIDs.contains($0.0.territoryID) }.map(\.1)
  }

  /// Territories' current automatic prices kept as manual ones from now on, so Apple no longer
  /// adjusts them (App Store Connect's "manually manage prices"). Territories already priced by hand
  /// stay as they are.
  public func keepingCurrent(territoryIDs: Set<String>) -> [AppPricing.NewPrice] {
    let today = AppPricing.today
    let manual = Set(manualPrices.filter { $0.applies(on: today) }.map(\.territoryID))
    let kept = automaticPrices.filter {
      $0.applies(on: today) && territoryIDs.contains($0.territoryID) && !manual.contains($0.territoryID)
    }
    return newPrices + kept.map { AppPricing.NewPrice(pricePointID: $0.point.id) }
  }

  /// A temporary price change (a sale): the territories' tiers from `start` until `end`
  /// (yyyy-MM-dd). Each territory's prices before and after stay: a manual price is cut around the
  /// change, and where Apple set the price it does again afterwards.
  public func addingTemporary(pricePointIDs: [String: String], from start: String, until end: String) -> [AppPricing.NewPrice] {
    var prices: [AppPricing.NewPrice] = []
    for (price, new) in zip(manualPrices.filter(\.isCurrentOrLater), newPrices) {
      guard pricePointIDs[price.territoryID] != nil else {
        prices.append(new)
        continue
      }
      // The part before the change, and the part after it.
      if (new.startDate ?? "") < start {
        prices.append(AppPricing.NewPrice(
          pricePointID: new.pricePointID, startDate: new.startDate, endDate: new.endDate.map { min($0, start) } ?? start))
      }
      if new.endDate.map({ $0 > end }) ?? true {
        prices.append(AppPricing.NewPrice(
          pricePointID: new.pricePointID, startDate: max(new.startDate ?? end, end), endDate: new.endDate))
      }
    }
    let sale = pricePointIDs.sorted { $0.key < $1.key }.map { AppPricing.NewPrice(pricePointID: $0.value, startDate: start, endDate: end) }
    return prices + sale
  }

  /// A planned price removed; the price before it goes on until the one after it (or for good).
  public func removingPlanned(_ planned: AppPricing.Price) -> [AppPricing.NewPrice] {
    zip(manualPrices.filter(\.isCurrentOrLater), newPrices).compactMap { price, new in
      if price.id == planned.id { return nil }
      if price.territoryID == planned.territoryID, price.endDate == planned.startDate {
        return AppPricing.NewPrice(pricePointID: new.pricePointID, startDate: new.startDate, endDate: planned.endDate)
      }
      return new
    }
  }

  /// A price cut off on the day: dropped if it starts then or later, else ending then. Nil (now)
  /// drops it.
  private static func ending(_ price: AppPricing.NewPrice, on day: String?) -> AppPricing.NewPrice? {
    guard let day, (price.startDate ?? "") < day else { return nil }
    let end = price.endDate.map { min($0, day) } ?? day
    return AppPricing.NewPrice(pricePointID: price.pricePointID, startDate: price.startDate, endDate: end)
  }
}

extension AppPricing.Price {
  /// Whether it applies today or later (what `newPrices` keeps).
  public var isCurrentOrLater: Bool {
    endDate.map { $0 > AppPricing.today } ?? true
  }
}
